use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    sync::{Arc, Mutex},
};

use sea_orm::{ConnectionTrait, DatabaseConnection, TransactionTrait};
use tokio::sync::{Semaphore, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::{
    db::{self, Record},
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
    pub writer: DatabaseConnection,
    pub reader: DatabaseConnection,
    pub state: Mutex<State>,
    pub changed: watch::Sender<u64>,
    pub cancel: CancellationToken,
    pub operations: TaskTracker,
    pub(super) admission: tokio::sync::Mutex<()>,
    flush: tokio::sync::Mutex<()>,
    item_budget: Arc<Semaphore>,
    byte_budget: Arc<Semaphore>,
    limits: HistoryLimits,
    lease: Mutex<Option<std::fs::File>>,
}

#[derive(Clone)]
pub struct HistoryStore {
    pub(super) inner: Arc<Inner>,
}

impl std::fmt::Debug for HistoryStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStore")
            .field("thread_id", &self.inner.thread_id)
            .field("database_id", &self.inner.database_id)
            .finish_non_exhaustive()
    }
}

/// A coordinator-owned weak view of the one writer lease.
///
/// The registry must not extend a Thread's database lifetime. It only converges concurrent opens
/// while at least one production holder remains alive.
#[derive(Clone)]
pub struct HistoryStoreShare(std::sync::Weak<Inner>);

impl std::fmt::Debug for HistoryStoreShare {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HistoryStoreShare").finish_non_exhaustive()
    }
}

impl HistoryStore {
    /// Opens an independent, read-only reader without creating or registering a writer.
    ///
    /// The file must already exist and contain the current append-only schema. This path takes no
    /// writer lease and never consults current JSON, so it remains usable while another process owns
    /// the one writer connection.
    pub async fn open_reader(
        path: impl AsRef<Path>,
        thread_id: &str,
        limits: HistoryLimits,
    ) -> Result<HistoryReader> {
        if thread_id.is_empty() || limits.pending_events == 0 || limits.pending_bytes == 0 {
            return Err(HistoryError::InvalidEvent(
                "empty owner identity or capacity".into(),
            ));
        }
        let path = path.as_ref();
        let reader = schema::connect(path, true, false).await?;
        let (database_id, head) = schema::identity(&reader, thread_id).await?;
        let (changed, _) = watch::channel(head);
        let inner = Arc::new(Inner {
            thread_id: thread_id.to_owned(),
            read_only: true,
            database_id,
            // Reader-only stores never invoke writer paths; retaining the same read-only handle
            // keeps their capability visibly read-only instead of opening an unused writable pool.
            writer: reader.clone(),
            reader,
            state: Mutex::new(State {
                pending: Arc::new(Pending::default()),
                head,
                accepting: false,
                closing: false,
                write_error: None,
            }),
            changed,
            cancel: CancellationToken::new(),
            operations: TaskTracker::new(),
            admission: tokio::sync::Mutex::new(()),
            flush: tokio::sync::Mutex::new(()),
            item_budget: Arc::new(Semaphore::new(limits.pending_events as usize)),
            byte_budget: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
            limits,
            lease: Mutex::new(None),
        });
        Ok(HistoryReader::new(inner))
    }

    /// Opens this Thread's single registered history owner. Existing non-25 files are rejected
    /// read-only; production schema upgrades belong to the explicit migration boundary.
    pub async fn open(
        path: impl AsRef<Path>,
        thread_id: &str,
        limits: HistoryLimits,
    ) -> Result<Self> {
        if thread_id.is_empty() || limits.pending_events == 0 || limits.pending_bytes == 0 {
            return Err(HistoryError::InvalidEvent(
                "empty owner identity or capacity".into(),
            ));
        }
        let path = path.as_ref().to_path_buf();
        let parent = path
            .parent()
            .ok_or_else(|| HistoryError::InvalidEvent("history path has no parent".into()))?;
        tokio::fs::create_dir_all(parent).await?;
        let mut lock_path = path.as_os_str().to_os_string();
        lock_path.push(".writer.lock");
        let lease = tokio::task::spawn_blocking(move || -> Result<std::fs::File> {
            let file = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(lock_path)?;
            fs4::FileExt::try_lock(&file).map_err(|error| {
                HistoryError::Conflict(format!("history writer lease: {error}"))
            })?;
            Ok(file)
        })
        .await
        .map_err(|error| HistoryError::Storage(error.into()))??;
        let exists = match tokio::fs::metadata(&path).await {
            Ok(_) => true,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
            Err(error) => return Err(error.into()),
        };
        if exists {
            let read = schema::connect(&path, true, false).await?;
            let identity = schema::identity(&read, thread_id).await;
            read.close().await?;
            identity?;
        }
        let writer = schema::connect(&path, false, !exists).await?;
        if !exists {
            schema::initialize(&writer, thread_id).await?;
        }
        let (database_id, head) = schema::identity(&writer, thread_id).await?;
        let reader = schema::connect(&path, true, false).await?;
        let (changed, _) = watch::channel(head);
        Ok(Self {
            inner: Arc::new(Inner {
                thread_id: thread_id.to_owned(),
                read_only: false,
                database_id,
                writer,
                reader,
                state: Mutex::new(State {
                    pending: Arc::new(Pending::default()),
                    head,
                    accepting: true,
                    closing: false,
                    write_error: None,
                }),
                changed,
                cancel: CancellationToken::new(),
                operations: TaskTracker::new(),
                admission: tokio::sync::Mutex::new(()),
                flush: tokio::sync::Mutex::new(()),
                item_budget: Arc::new(Semaphore::new(limits.pending_events as usize)),
                byte_budget: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
                limits,
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
        let pending = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .pending
            .clone();
        if pending.anchors.contains_key(row) {
            return Ok(true);
        }
        Ok(db::anchor(&self.inner.reader, row).await?.is_some())
    }
    pub fn status(&self) -> HistoryStatus {
        let state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        HistoryStatus {
            pending_events: state.pending.events.len(),
            pending_bytes: state.pending.bytes,
            retained_events: self.inner.limits.pending_events as usize
                - self.inner.item_budget.available_permits(),
            retained_bytes: self.inner.limits.pending_bytes as usize
                - self.inner.byte_budget.available_permits(),
            write_error: state.write_error.clone(),
            accepting: state.accepting,
        }
    }

    fn observe_status(&self, committed: bool) {
        if tracing::enabled!(target: "conversation_work", tracing::Level::DEBUG) {
            let status = self.status();
            tracing::debug!(target: "conversation_work",
                history_pending_events = status.pending_events,
                history_pending_bytes = status.pending_bytes,
                history_retained_events = status.retained_events,
                history_retained_bytes = status.retained_bytes,
                committed,
                "history pending and retained memory"
            );
        }
    }
    /// Atomic, bounded acceptance. Capacity is explicit so the producer can keep processing
    /// cancellation/current saves while its existing pressure mechanism pauses new archive work.
    pub async fn accept_batch(&self, events: &[HistoryEvent]) -> Result<Vec<u64>> {
        let admission = self.admission_guard().await;
        self.accept_locked(&admission, events).await
    }

    /// Takes the same admission boundary used by [`Self::accept_batch`].
    ///
    /// Producer-specific preparation (classifier and usage folding) needs to inspect the pending
    /// root while no other admission can interleave. Those callers may then call the non-locking
    /// [`Self::accept_locked`] with the complete candidate effect, avoiding recursive acquisition.
    pub(crate) async fn admission_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.inner.admission.lock().await
    }

    pub(crate) async fn accept_locked(
        &self,
        _admission: &tokio::sync::MutexGuard<'_, ()>,
        events: &[HistoryEvent],
    ) -> Result<Vec<u64>> {
        let pending = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !state.accepting {
                return Err(HistoryError::Closed);
            }
            state.pending.clone()
        };
        let mut ids = BTreeSet::new();
        let mut body_ids = BTreeSet::new();
        let mut new = Vec::new();
        let mut sequences = Vec::with_capacity(events.len());
        let mut bytes = 0usize;
        let tx = self.inner.reader.begin().await?;
        for event in events {
            let retained = validate::event(event)?;
            if !ids.insert(&event.header.event_id) {
                return Err(HistoryError::Conflict(
                    "duplicate event identity within a batch".into(),
                ));
            }
            if let Some(old) = pending.event(&event.header.event_id) {
                let mut candidate = event.clone();
                candidate.header.seq = old.event.header.seq;
                if candidate != old.event {
                    return Err(HistoryError::Conflict(event.header.event_id.clone()));
                }
                sequences.push(Some(old.event.header.seq));
            } else if let Some(old) = db::event(&tx, &event.header.event_id).await? {
                same_committed(&tx, event, &old).await?;
                sequences.push(Some(old.header.seq));
            } else {
                sequences.push(None);
                bytes = bytes.checked_add(retained).ok_or(HistoryError::Capacity)?;
                new.push((event, retained));
                for body in &event.bodies {
                    if !body_ids.insert(&body.body_id)
                        || pending.bodies.contains_key(&body.body_id)
                        || db::body(&tx, &body.body_id).await?.is_some()
                    {
                        return Err(HistoryError::Conflict(body.body_id.clone()));
                    }
                }
            }
        }
        let batch: BTreeMap<_, _> = events
            .iter()
            .map(|event| (event.header.event_id.as_str(), event))
            .collect();
        let mut anchors = BTreeSet::new();
        let mut closed_groups = BTreeSet::new();
        for (event, _) in &new {
            if let Some(row) = &event.header.row_key {
                let exists = anchors.contains(row)
                    || pending.anchors.contains_key(row)
                    || db::anchor(&tx, row).await?.is_some();
                if event.is_anchor == exists {
                    return Err(HistoryError::Conflict(format!("row anchor {row}")));
                }
                if event.is_anchor {
                    anchors.insert(row.clone());
                }
            }
            check_references(&tx, &pending, &batch, event, &self.inner.database_id).await?;
            if let Some(group) = &event.header.group_id {
                if closed_groups.contains(group) {
                    return Err(HistoryError::InvalidEvent(
                        "cannot append after a group closed in this batch".into(),
                    ));
                }
                let key = format!("work:{group}");
                let latest = pending
                    .head(&key, u64::MAX)
                    .map(|accepted| Record::from_event(&accepted.event));
                let latest = match latest {
                    Some(record) => Some(record),
                    None => db::head(&tx, &key, i64::MAX as u64).await?,
                };
                if matches!(latest.as_ref().and_then(|record| record.head.as_ref()), Some(HistoryRowHead::Work(head)) if head.closed)
                {
                    return Err(HistoryError::InvalidEvent(
                        "cannot append to a closed work group".into(),
                    ));
                }
                if matches!(latest.as_ref().and_then(|record| record.head.as_ref()), Some(HistoryRowHead::Work(head)) if head.run_id != event.header.run_id)
                {
                    return Err(HistoryError::InvalidEvent(
                        "work group cannot cross runtime epochs".into(),
                    ));
                }
                if matches!(&event.head, Some(HistoryRowHead::Work(head)) if head.closed) {
                    closed_groups.insert(group.clone());
                }
            }
        }
        tx.commit().await?;
        if new.is_empty() {
            return Ok(sequences.into_iter().flatten().collect());
        }
        let reservation = Arc::new(Reservation {
            _events: self
                .inner
                .item_budget
                .clone()
                .try_acquire_many_owned(
                    u32::try_from(new.len()).map_err(|_| HistoryError::Capacity)?,
                )
                .map_err(|_| HistoryError::Capacity)?,
            _bytes: self
                .inner
                .byte_budget
                .clone()
                .try_acquire_many_owned(u32::try_from(bytes).map_err(|_| HistoryError::Capacity)?)
                .map_err(|_| HistoryError::Capacity)?,
        });
        let prepared = new
            .into_iter()
            .map(|(event, retained)| (event.clone(), retained))
            .collect::<Vec<_>>();
        let hash_reservation = reservation.clone();
        let hash_task = self.inner.operations.token();
        let (prepared, _hash_reservation) = tokio::task::spawn_blocking(move || {
            let _hash_task = hash_task;
            let prepared = prepared
                .into_iter()
                .map(|(event, retained)| {
                    let bodies = (0..event.bodies.len())
                        .map(|ordinal| db::Body::from_event(&event, ordinal))
                        .collect::<Vec<_>>();
                    (event, bodies, retained)
                })
                .collect::<Vec<_>>();
            (prepared, hash_reservation)
        })
        .await
        .map_err(|error| HistoryError::Storage(error.into()))?;
        let mut state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.accepting {
            return Err(HistoryError::Closed);
        }
        let final_head = state
            .head
            .checked_add(prepared.len() as u64)
            .filter(|head| *head <= i64::MAX as u64)
            .ok_or_else(|| HistoryError::InvalidEvent("history sequence exhausted".into()))?;
        let mut seq = state.head;
        for (mut event, body_headers, retained_bytes) in prepared {
            seq += 1;
            event.header.seq = seq;
            Arc::make_mut(&mut state.pending).insert(Arc::new(Accepted {
                event,
                retained_bytes,
                body_headers,
                _reservation: reservation.clone(),
            }))?;
        }
        for sequence in &mut sequences {
            if sequence.is_none() {
                *sequence = Some(state.head + 1);
                state.head += 1;
            }
        }
        state.head = final_head;
        self.inner.changed.send_replace(final_head);
        drop(state);
        self.observe_status(false);
        Ok(sequences.into_iter().flatten().collect())
    }
    pub(super) async fn latest_record(&self, row: &str) -> Result<Option<Record>> {
        let (head, pending) = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (state.head, state.pending.clone())
        };
        if let Some(accepted) = pending.head(row, head) {
            return Ok(Some(Record::from_event(&accepted.event)));
        }
        db::head(&self.inner.reader, row, head).await
    }
    /// A failed or cancelled transaction leaves the same pending events available for retry.
    /// New accepted batches may arrive during IO and are not acknowledged by this flush.
    pub async fn flush(&self) -> Result<()> {
        let _flush = self.inner.flush.lock().await;
        let snapshot = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .pending
            .clone();
        if snapshot.events.is_empty() {
            return Ok(());
        }
        let through = *snapshot
            .events
            .last_key_value()
            .expect("nonempty pending")
            .0;
        let result = async {
            let tx = self.inner.writer.begin().await?;
            for accepted in snapshot.events.values() {
                if let Some(old) = db::event(&tx, &accepted.event.header.event_id).await? {
                    same_committed(&tx, &accepted.event, &old).await?;
                } else {
                    db::insert(&tx, &accepted.event, &accepted.body_headers).await?;
                }
            }
            tx.commit().await?;
            Ok::<_, HistoryError>(())
        }
        .await;
        let mut state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Err(error) = &result {
            state.write_error = Some(error.to_string());
        } else {
            Arc::make_mut(&mut state.pending).remove_through(through)?;
            state.write_error = None;
        }
        drop(state);
        drop(snapshot);
        self.observe_status(result.is_ok());
        result
    }
    pub async fn close(&self) -> Result<()> {
        {
            let _admission = self.inner.admission.lock().await;
            let mut state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.accepting = false;
            state.closing = true;
            self.inner.operations.close();
            self.inner.cancel.cancel();
        }
        self.inner.operations.wait().await;
        self.flush().await?;
        self.inner.reader.clone().close().await?;
        self.inner.writer.clone().close().await?;
        self.inner
            .lease
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        Ok(())
    }
}

async fn same_committed(
    db: &impl ConnectionTrait,
    candidate: &HistoryEvent,
    old: &Record,
) -> Result<()> {
    if candidate.header.seq != 0 && candidate.header.seq != old.header.seq {
        return Err(HistoryError::Conflict(
            "retry changed the original history sequence".into(),
        ));
    }
    let mut record = Record::from_event(candidate);
    record.header.seq = old.header.seq;
    if record != *old {
        return Err(HistoryError::Conflict(candidate.header.event_id.clone()));
    }
    let stored = db::bodies(
        db,
        &candidate.header.event_id,
        None,
        candidate.bodies.len() + 1,
    )
    .await?;
    if stored.len() != candidate.bodies.len() {
        return Err(HistoryError::Conflict(candidate.header.event_id.clone()));
    }
    for (ordinal, body) in stored.iter().enumerate() {
        if *body != db::Body::from_event(candidate, ordinal) {
            return Err(HistoryError::Conflict(body.id.clone()));
        }
        let incoming = &candidate.bodies[ordinal].bytes;
        for (chunk, bytes) in incoming.chunks(BODY_CHUNK_BYTES).enumerate() {
            if db::window(db, body, (chunk * BODY_CHUNK_BYTES) as u64, bytes.len()).await? != bytes
            {
                return Err(HistoryError::Conflict(body.id.clone()));
            }
        }
    }
    Ok(())
}

async fn check_references(
    db: &impl ConnectionTrait,
    pending: &Pending,
    batch: &BTreeMap<&str, &HistoryEvent>,
    event: &HistoryEvent,
    database: &str,
) -> Result<()> {
    let (events, bodies) = validate::references(event);
    for id in events {
        if !batch.contains_key(id)
            && pending.event(id).is_none()
            && db::event(db, id).await?.is_none()
        {
            return Err(HistoryError::InvalidEvent(format!(
                "referenced event {id} is missing"
            )));
        }
    }
    for reference in bodies {
        let body = if let Some(event) = batch.get(reference.owner_event_id.as_str()) {
            event
                .bodies
                .iter()
                .position(|body| body.body_id == reference.body_id)
                .map(|ordinal| db::Body::from_event(event, ordinal))
        } else if let Some((seq, ordinal)) = pending.bodies.get(&reference.body_id) {
            Some(pending.events[seq].body_headers[*ordinal].clone())
        } else {
            db::body(db, &reference.body_id).await?
        };
        let body =
            body.ok_or_else(|| HistoryError::InvalidEvent("referenced body is missing".into()))?;
        if reference.database_id != database
            || reference.owner_event_id != body.owner
            || reference.body_key != body.key
            || reference
                .byte_start
                .checked_add(reference.byte_length)
                .is_none_or(|end| end > body.length)
        {
            return Err(HistoryError::InvalidEvent(
                "foreign or invalid body reference".into(),
            ));
        }
    }
    Ok(())
}
