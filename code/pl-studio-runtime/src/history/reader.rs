use std::{
    collections::BTreeMap,
    future::Future,
    sync::{Arc, Mutex},
};

use sea_orm::{DatabaseTransaction, TransactionTrait};
use sha2::{Digest, Sha256};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::Instrument;

use super::{
    db::{self, Body, Record},
    pending::Pending,
    store::Inner,
    token::{Codec, Query, Token},
    *,
};

struct ReaderState {
    closed: bool,
}
struct ReaderInner {
    store: Arc<Inner>,
    codec: Codec,
    cancel: CancellationToken,
    tasks: TaskTracker,
    state: Mutex<ReaderState>,
}

#[derive(Clone)]
pub struct HistoryReader {
    inner: Arc<ReaderInner>,
}
struct Snapshot {
    head: u64,
    pending: Arc<Pending>,
    tx: DatabaseTransaction,
}

impl HistoryReader {
    pub(super) fn new(store: Arc<Inner>) -> Self {
        Self {
            inner: Arc::new(ReaderInner {
                codec: Codec::new(&store.database_id),
                store,
                cancel: CancellationToken::new(),
                tasks: TaskTracker::new(),
                state: Mutex::new(ReaderState { closed: false }),
            }),
        }
    }
    pub fn database_id(&self) -> &str {
        &self.inner.store.database_id
    }
    async fn run<T, F>(&self, make: impl FnOnce(Self) -> F + Send + 'static) -> Result<T>
    where
        T: Send + 'static,
        F: Future<Output = Result<T>> + Send + 'static,
    {
        let request_cancel = CancellationToken::new();
        let _cancel = request_cancel.clone().drop_guard();
        let task = {
            let store = self
                .inner
                .store
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let reader = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if reader.closed || store.closing {
                return Err(HistoryError::Closed);
            }
            let store_task = self.inner.store.operations.token();
            let owner = self.clone();
            // Register before releasing either admission gate. Caller cancellation cannot detach
            // an untracked database operation from the capability's close/join lifecycle.
            self.inner.tasks.spawn(async move {
                let result = tokio::select! {
                    biased;
                    _ = request_cancel.cancelled() => Err(HistoryError::Closed),
                    _ = owner.inner.cancel.cancelled() => Err(HistoryError::Closed),
                    _ = owner.inner.store.cancel.cancelled() => Err(HistoryError::Closed),
                    result = make(owner.clone()).instrument(tracing::debug_span!(
                        target: "conversation_work", "history_read",
                        thread_id = owner.inner.store.thread_id,
                    )) => result,
                };
                drop(store_task);
                result
            })
        };
        task.await
            .map_err(|error| HistoryError::Storage(error.into()))?
    }
    async fn snapshot(&self) -> Result<Snapshot> {
        let (head, pending) = {
            let state = self
                .inner
                .store
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (state.head, state.pending.clone())
        };
        // No transaction or read snapshot can predate the pending root capture.
        let tx = self.inner.store.reader.begin().await?;
        let head = if self.inner.store.read_only {
            db::event_head(&tx).await?
        } else {
            head
        };
        Ok(Snapshot { head, pending, tx })
    }
    pub async fn capture(&self) -> Result<HistoryCut> {
        self.capture_position().await.map(|(cut, _)| cut)
    }
    /// The opaque accepted cut and its event position; this is not a persistence ACK.
    /// Writable owners capture their RAM head without opening a database transaction.
    pub async fn capture_position(&self) -> Result<(HistoryCut, u64)> {
        if !self.inner.store.read_only {
            let state = self
                .inner
                .store
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let reader = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if reader.closed || state.closing {
                return Err(HistoryError::Closed);
            }
            return Ok((self.inner.codec.cut(state.head)?, state.head));
        }
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            let cut = reader.inner.codec.cut(snapshot.head)?;
            let head = snapshot.head;
            snapshot.tx.commit().await?;
            Ok((cut, head))
        })
        .await
    }
    /// The accepted event head, or the current committed head for a cold read-only capability.
    pub async fn head(&self) -> Result<u64> {
        self.capture_position().await.map(|(_, head)| head)
    }
    fn page_cut(
        &self,
        query: &Query,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        head: u64,
    ) -> Result<(HistoryCut, u64, Option<u64>)> {
        let (cut, before) = if let Some(cursor) = cursor {
            match self.inner.codec.decode(&cursor)? {
                Token::Page {
                    cut: saved,
                    query: saved_query,
                    before,
                } if saved_query == *query && cut.as_ref().is_none_or(|cut| cut == &saved) => {
                    (saved, Some(before))
                }
                _ => return Err(HistoryError::InvalidCursor),
            }
        } else {
            (cut.unwrap_or(self.inner.codec.cut(head)?), None)
        };
        let through = self.inner.codec.through(&cut)?;
        if through > head {
            return Err(HistoryError::InvalidCursor);
        }
        Ok((cut, through, before))
    }
    fn next(&self, cut: &HistoryCut, query: &Query, before: u64) -> Result<String> {
        self.inner.codec.encode(Token::Page {
            cut: cut.clone(),
            query: query.clone(),
            before,
        })
    }
    pub async fn timeline_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.run(move |reader| async move { reader.rows(Query::Main, cut, cursor, demand).await })
            .await
    }
    pub async fn group_page(
        &self,
        group_id: String,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryGroupPage> {
        if group_id.is_empty() {
            return Err(HistoryError::InvalidDemand("empty group identity".into()));
        }
        self.run(move |reader| async move {
            let page = reader
                .rows(Query::Group(group_id.clone()), cut, cursor, demand)
                .await?;
            Ok(HistoryGroupPage {
                cut: page.cut,
                group_id,
                members: page.entries,
                next: page.next,
            })
        })
        .await
    }
    pub async fn turns_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.run(move |reader| async move {
            reader
                .rows(Query::Rows("turn".into()), cut, cursor, demand)
                .await
        })
        .await
    }
    pub async fn costs_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.run(move |reader| async move {
            reader
                .rows(Query::Rows("cost".into()), cut, cursor, demand)
                .await
        })
        .await
    }
    async fn rows(
        &self,
        query: Query,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        demand.validate()?;
        let snapshot = self.snapshot().await?;
        let (cut, through, before) = self.page_cut(&query, cut, cursor, snapshot.head)?;
        let limit = demand.max_rows as usize;
        let database = db::anchors(&snapshot.tx, &query, through, before, limit).await?;
        let pending = snapshot
            .pending
            .candidates(&query, through, before, limit)?;
        let mut candidates: BTreeMap<u64, String> = database.into_iter().collect();
        for event in pending {
            let row = event
                .event
                .header
                .row_key
                .clone()
                .ok_or_else(|| HistoryError::Integrity("pending anchor has no row".into()))?;
            if let Some(old) = candidates.insert(event.event.header.seq, row.clone())
                && old != row
            {
                return Err(HistoryError::Integrity(
                    "RAM and database anchors differ".into(),
                ));
            }
        }
        let exhausted = candidates.len() < limit;
        let candidate_count = candidates.len().min(limit);
        let mut entry_bytes = 0;
        let mut page = HistoryTimelinePage {
            cut,
            entries: Vec::new(),
            next: None,
        };
        let mut examined = 0usize;
        for (index, (anchor_seq, row_key)) in candidates.into_iter().rev().take(limit).enumerate() {
            examined += 1;
            let head = latest_head(&snapshot, &row_key, through)
                .await?
                .ok_or_else(|| HistoryError::Integrity("anchor has no head at its cut".into()))?;
            let entry = HistoryTimelineEntry {
                row_key,
                anchor_seq,
                head_seq: head.header.seq,
                head: head
                    .head
                    .ok_or_else(|| HistoryError::Integrity("row has no typed head".into()))?,
            };
            let previous_next = page.next.clone();
            page.next = if exhausted && index + 1 == candidate_count {
                None
            } else {
                Some(self.next(&page.cut, &query, anchor_seq)?)
            };
            entry_bytes += serde_json::to_vec(&entry)?.len();
            page.entries.push(entry);
            let fits = if let Query::Group(group_id) = &query {
                fits_entries(
                    demand,
                    &HistoryGroupPage {
                        cut: page.cut.clone(),
                        group_id: group_id.clone(),
                        members: Vec::new(),
                        next: page.next.clone(),
                    },
                    entry_bytes,
                    page.entries.len(),
                )?
            } else {
                fits_entries(
                    demand,
                    &HistoryTimelinePage {
                        cut: page.cut.clone(),
                        entries: Vec::new(),
                        next: page.next.clone(),
                    },
                    entry_bytes,
                    page.entries.len(),
                )?
            };
            if !fits {
                page.entries.pop();
                page.next = previous_next;
                if page.entries.is_empty() {
                    return Err(HistoryError::InvalidDemand(
                        "page cannot fit its first row and continuation".into(),
                    ));
                }
                observe_page(&query, &page, examined)?;
                snapshot.tx.commit().await?;
                return Ok(page);
            }
        }
        if exhausted {
            page.next = None;
        }
        let fits = if let Query::Group(group_id) = &query {
            fits_entries(
                demand,
                &HistoryGroupPage {
                    cut: page.cut.clone(),
                    group_id: group_id.clone(),
                    members: Vec::new(),
                    next: page.next.clone(),
                },
                entry_bytes,
                page.entries.len(),
            )?
        } else {
            demand.fits(&page)?
        };
        if !fits {
            return Err(HistoryError::InvalidDemand(
                "page envelope exceeds budget".into(),
            ));
        }
        observe_page(&query, &page, examined)?;
        snapshot.tx.commit().await?;
        Ok(page)
    }
    pub async fn events_page(
        &self,
        query: HistoryEventsQuery,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryEventsPage> {
        self.run(move |reader| async move {
            demand.validate()?;
            validate::query(&query)?;
            let snapshot = reader.snapshot().await?;
            let query = Query::Events(query);
            let (cut, through, before) = reader.page_cut(&query, cut, cursor, snapshot.head)?;
            let limit = demand.max_rows as usize;
            let database = db::candidates(&snapshot.tx, &query, through, before, limit).await?;
            let pending = snapshot
                .pending
                .candidates(&query, through, before, limit)?;
            let mut candidates: BTreeMap<_, _> = database
                .into_iter()
                .map(|event| (event.header.seq, event))
                .collect();
            for accepted in pending {
                let event = Record::from_event(&accepted.event);
                if let Some(old) = candidates.insert(event.header.seq, event.clone())
                    && old != event
                {
                    return Err(HistoryError::Integrity(
                        "RAM and database event differ".into(),
                    ));
                }
            }
            let exhausted = candidates.len() < limit;
            let candidate_count = candidates.len().min(limit);
            let mut entry_bytes = 0;
            let mut page = HistoryEventsPage {
                cut,
                entries: Vec::new(),
                next: None,
            };
            for (index, (seq, event)) in candidates.into_iter().rev().take(limit).enumerate() {
                let detail = reader.detail(&snapshot, event).await?;
                let previous_next = page.next.clone();
                page.next = if exhausted && index + 1 == candidate_count {
                    None
                } else {
                    Some(reader.next(&page.cut, &query, seq)?)
                };
                entry_bytes += serde_json::to_vec(&detail)?.len();
                page.entries.push(detail);
                if !fits_entries(
                    demand,
                    &HistoryEventsPage {
                        cut: page.cut.clone(),
                        entries: Vec::new(),
                        next: page.next.clone(),
                    },
                    entry_bytes,
                    page.entries.len(),
                )? {
                    page.entries.pop();
                    page.next = previous_next;
                    if page.entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "event page cannot fit its first record".into(),
                        ));
                    }
                    snapshot.tx.commit().await?;
                    return Ok(page);
                }
            }
            if exhausted {
                page.next = None;
            }
            if !demand.fits(&page)? {
                return Err(HistoryError::InvalidDemand(
                    "event page envelope exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(page)
        })
        .await
    }
    /// Native consumers have their own bounded, authenticated business cursor. They select a
    /// fixed event cut and use the same indexed query engine in either direction, without creating
    /// a durable completion allocator or walking a descending history to serve an ascending page.
    pub(crate) async fn events_window(
        &self,
        query: HistoryEventsQuery,
        through: Option<u64>,
        pivot: Option<u64>,
        ascending: bool,
        demand: HistoryDemand,
    ) -> Result<(u64, Vec<HistoryEventDetail>, bool)> {
        self.run(move |reader| async move {
            demand.validate()?;
            validate::query(&query)?;
            let snapshot = reader.snapshot().await?;
            let through = through.unwrap_or(snapshot.head);
            if through > snapshot.head {
                return Err(HistoryError::InvalidCursor);
            }
            let query = Query::Events(query);
            let limit = demand.max_rows as usize;
            let stored =
                db::candidates_in_order(&snapshot.tx, &query, through, pivot, limit, ascending)
                    .await?;
            let pending = snapshot
                .pending
                .candidates_in_order(&query, through, pivot, limit, ascending)?;
            let mut candidates: BTreeMap<u64, Record> = stored
                .into_iter()
                .map(|event| (event.header.seq, event))
                .collect();
            for event in pending {
                let event = Record::from_event(&event.event);
                if let Some(old) = candidates.insert(event.header.seq, event.clone())
                    && old != event
                {
                    return Err(HistoryError::Integrity(
                        "RAM and stored original differ".into(),
                    ));
                }
            }
            let mut has_more = candidates.len() >= limit;
            let order: Box<dyn Iterator<Item = (u64, Record)> + Send> = if ascending {
                Box::new(candidates.into_iter())
            } else {
                Box::new(candidates.into_iter().rev())
            };
            let mut entries = Vec::new();
            let mut bytes = 64;
            for (_, event) in order.take(limit) {
                let detail = reader.detail(&snapshot, event).await?;
                let size = serde_json::to_vec(&detail)?.len() + 1;
                if bytes + size > demand.max_bytes as usize {
                    if entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "original window cannot fit its first event".into(),
                        ));
                    }
                    has_more = true;
                    break;
                }
                bytes += size;
                entries.push(detail);
            }
            snapshot.tx.commit().await?;
            Ok((through, entries, has_more))
        })
        .await
    }

    async fn detail(&self, snapshot: &Snapshot, event: Record) -> Result<HistoryEventDetail> {
        let payload_ref = if let Some(id) = &event.payload_body_id {
            Some(
                resolve_body(snapshot, id)
                    .await?
                    .ok_or_else(|| HistoryError::Integrity("event payload body is missing".into()))?
                    .reference(&self.inner.store.database_id),
            )
        } else {
            None
        };
        let owns = if let Some(accepted) = snapshot.pending.event(&event.header.event_id) {
            !accepted.event.bodies.is_empty()
        } else {
            !db::bodies(&snapshot.tx, &event.header.event_id, None, 1)
                .await?
                .is_empty()
        };
        Ok(HistoryEventDetail {
            owned_manifest_event_id: owns.then(|| event.header.event_id.clone()),
            header: event.header,
            head: event.head,
            payload_ref,
        })
    }
    pub async fn read_event(
        &self,
        event_id: String,
        demand: HistoryDemand,
    ) -> Result<HistoryEventDetail> {
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let event = resolve_event(&snapshot, &event_id)
                .await?
                .ok_or_else(|| HistoryError::NotFound(event_id))?;
            let detail = reader.detail(&snapshot, event).await?;
            if !demand.fits(&detail)? {
                return Err(HistoryError::InvalidDemand(
                    "event detail exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(detail)
        })
        .await
    }

    /// Returns the canonical original event for one entity.
    ///
    /// Entity lifecycle events may be appended after the canonical payload; a plain latest-entity
    /// lookup would therefore hide the completed original. Only rows carrying `query_class` are
    /// considered here.
    pub async fn original_for_entity(
        &self,
        entity_id: String,
        demand: HistoryDemand,
    ) -> Result<Option<HistoryEventDetail>> {
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let pending = snapshot
                .pending
                .events
                .values()
                .rev()
                .find(|accepted| {
                    accepted.event.header.entity_id.as_deref() == Some(&entity_id)
                        && accepted.event.header.original.is_some()
                })
                .map(|accepted| Record::from_event(&accepted.event));
            let event = match (
                pending,
                db::original_by_entity(&snapshot.tx, &entity_id, snapshot.head).await?,
            ) {
                (Some(pending), Some(database)) if pending.header.seq > database.header.seq => {
                    Some(pending)
                }
                (_, Some(database)) => Some(database),
                (pending, None) => pending,
            };
            let detail = match event {
                None => None,
                Some(event) => Some(reader.detail(&snapshot, event).await?),
            };
            if let Some(detail) = &detail
                && !demand.fits(detail)?
            {
                return Err(HistoryError::InvalidDemand(
                    "event detail exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(detail)
        })
        .await
    }

    /// Returns the newest canonical original event, including RAM-pending events.
    pub async fn latest_original(
        &self,
        demand: HistoryDemand,
    ) -> Result<Option<HistoryEventDetail>> {
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let pending = snapshot
                .pending
                .events
                .values()
                .rev()
                .find(|accepted| accepted.event.header.original.is_some())
                .map(|accepted| Record::from_event(&accepted.event));
            let event = match (
                pending,
                db::latest_original(&snapshot.tx, snapshot.head).await?,
            ) {
                (Some(pending), Some(database)) if pending.header.seq > database.header.seq => {
                    Some(pending)
                }
                (_, Some(database)) => Some(database),
                (pending, None) => pending,
            };
            let detail = match event {
                None => None,
                Some(event) => Some(reader.detail(&snapshot, event).await?),
            };
            if let Some(detail) = &detail
                && !demand.fits(detail)?
            {
                return Err(HistoryError::InvalidDemand(
                    "original detail exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(detail)
        })
        .await
    }
    pub async fn latest_row(
        &self,
        row_key: String,
        demand: HistoryDemand,
    ) -> Result<Option<HistoryEventDetail>> {
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let pending = snapshot
                .pending
                .head(&row_key, snapshot.head)
                .map(|accepted| Record::from_event(&accepted.event));
            let event = match (
                pending,
                db::head(&snapshot.tx, &row_key, snapshot.head).await?,
            ) {
                (Some(pending), Some(database)) if pending.header.seq > database.header.seq => {
                    Some(pending)
                }
                (_, Some(database)) => Some(database),
                (pending, None) => pending,
            };
            let detail = match event {
                None => None,
                Some(event) => Some(reader.detail(&snapshot, event).await?),
            };
            if let Some(detail) = &detail
                && !demand.fits(detail)?
            {
                return Err(HistoryError::InvalidDemand(
                    "row detail exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(detail)
        })
        .await
    }
    pub async fn list_bodies(
        &self,
        event_id: String,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBodyPage> {
        self.run(move |reader| async move {
            demand.validate()?;
            let after = match cursor {
                None => None,
                Some(cursor) => match reader.inner.codec.decode(&cursor)? {
                    Token::Bodies {
                        event_id: saved,
                        after,
                    } if saved == event_id => Some(after),
                    _ => return Err(HistoryError::InvalidCursor),
                },
            };
            let snapshot = reader.snapshot().await?;
            resolve_event(&snapshot, &event_id)
                .await?
                .ok_or_else(|| HistoryError::NotFound(event_id.clone()))?;
            let limit = demand.max_rows as usize;
            let bodies = if let Some(accepted) = snapshot.pending.event(&event_id) {
                let start = match after {
                    None => 0,
                    Some(after) => {
                        usize::try_from(after.checked_add(1).ok_or(HistoryError::InvalidCursor)?)
                            .map_err(|_| HistoryError::InvalidCursor)?
                    }
                };
                (start..accepted.event.bodies.len())
                    .take(limit)
                    .map(|ordinal| accepted.body_headers[ordinal].clone())
                    .collect()
            } else {
                db::bodies(&snapshot.tx, &event_id, after, limit).await?
            };
            let exhausted = bodies.len() < limit;
            let candidate_count = bodies.len();
            let mut entry_bytes = 0;
            let mut page = HistoryBodyPage {
                owner_event_id: event_id,
                entries: Vec::new(),
                next: None,
            };
            for (index, body) in bodies.into_iter().enumerate() {
                let previous_next = page.next.clone();
                page.next = if exhausted && index + 1 == candidate_count {
                    None
                } else {
                    Some(reader.inner.codec.encode(Token::Bodies {
                        event_id: page.owner_event_id.clone(),
                        after: body.ordinal,
                    })?)
                };
                let entry = body.entry(&reader.inner.store.database_id);
                entry_bytes += serde_json::to_vec(&entry)?.len();
                page.entries.push(entry);
                if !fits_entries(
                    demand,
                    &HistoryBodyPage {
                        owner_event_id: page.owner_event_id.clone(),
                        entries: Vec::new(),
                        next: page.next.clone(),
                    },
                    entry_bytes,
                    page.entries.len(),
                )? {
                    page.entries.pop();
                    page.next = previous_next;
                    if page.entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "body page cannot fit its first entry".into(),
                        ));
                    }
                    snapshot.tx.commit().await?;
                    return Ok(page);
                }
            }
            if exhausted {
                page.next = None;
            }
            if !demand.fits(&page)? {
                return Err(HistoryError::InvalidDemand(
                    "body page envelope exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(page)
        })
        .await
    }
    pub async fn read_body(
        &self,
        reference: HistoryEventBodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<HistoryBodyWindow> {
        self.run(move |reader| async move {
            if max_bytes == 0 || max_bytes as usize > BODY_CHUNK_BYTES {
                return Err(HistoryError::InvalidDemand(
                    "body window must be 1..65536 bytes".into(),
                ));
            }
            let snapshot = reader.snapshot().await?;
            let body = reader.authorize_body(&snapshot, &reference).await?;
            if offset > reference.byte_length {
                return Err(HistoryError::InvalidDemand(
                    "offset exceeds body slice".into(),
                ));
            }
            let length = (reference.byte_length - offset).min(max_bytes as u64) as usize;
            let start = reference.byte_start + offset;
            let bytes = if let Some((seq, ordinal)) = snapshot.pending.bodies.get(&body.id) {
                tracing::debug!(target: "conversation_work",
                    history_body_bytes_read = length, source = "pending",
                    "history pending body slice copied"
                );
                snapshot.pending.events[seq].event.bodies[*ordinal].bytes
                    [start as usize..start as usize + length]
                    .to_vec()
            } else {
                db::window(&snapshot.tx, &body, start, length).await?
            };
            tracing::debug!(target: "conversation_work",
                history_body_returned_bytes = bytes.len(), offset,
                history_body_from_pending = snapshot.pending.bodies.contains_key(&body.id),
                "history body range read"
            );
            snapshot.tx.commit().await?;
            Ok(HistoryBodyWindow {
                offset,
                bytes,
                total_length: reference.byte_length,
                media_type: body.media_type,
            })
        })
        .await
    }
    async fn authorize_body(
        &self,
        snapshot: &Snapshot,
        reference: &HistoryEventBodyRef,
    ) -> Result<Body> {
        if reference.database_id != self.inner.store.database_id {
            return Err(HistoryError::InvalidCursor);
        }
        let body = resolve_body(snapshot, &reference.body_id)
            .await?
            .ok_or_else(|| HistoryError::NotFound(reference.body_id.clone()))?;
        if body.owner != reference.owner_event_id
            || body.key != reference.body_key
            || reference
                .byte_start
                .checked_add(reference.byte_length)
                .is_none_or(|end| end > body.length)
        {
            return Err(HistoryError::InvalidCursor);
        }
        resolve_event(snapshot, &body.owner)
            .await?
            .ok_or_else(|| HistoryError::Integrity("body owner is missing".into()))?;
        Ok(body)
    }
    /// Explicit full-body integrity check, streamed in fixed chunks. Ordinary range reads stay
    /// bounded and do not read an entire large body merely to recompute its global SHA-256.
    pub async fn verify_body(&self, reference: HistoryEventBodyRef) -> Result<()> {
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            let body = reader.authorize_body(&snapshot, &reference).await?;
            let mut hash = Sha256::new();
            let mut offset = 0;
            while offset < body.length {
                let length = (body.length - offset).min(BODY_CHUNK_BYTES as u64) as usize;
                if let Some((seq, ordinal)) = snapshot.pending.bodies.get(&body.id) {
                    hash.update(
                        &snapshot.pending.events[seq].event.bodies[*ordinal].bytes
                            [offset as usize..offset as usize + length],
                    );
                } else {
                    hash.update(db::window(&snapshot.tx, &body, offset, length).await?);
                }
                offset += length as u64;
            }
            if hash.finalize().as_slice() != body.digest {
                return Err(HistoryError::Integrity("body digest differs".into()));
            }
            snapshot.tx.commit().await?;
            Ok(())
        })
        .await
    }
    pub async fn accounting(
        &self,
        cut: Option<HistoryCut>,
    ) -> Result<Option<HistoryAccountingHead>> {
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            let through = match cut {
                Some(cut) => reader.inner.codec.through(&cut)?,
                None => snapshot.head,
            };
            if through > snapshot.head {
                return Err(HistoryError::InvalidCursor);
            }
            let head = latest_head(&snapshot, "accounting:session", through).await?;
            let result = match head.and_then(|record| record.head) {
                None => None,
                Some(HistoryRowHead::Accounting(head)) => Some(head),
                Some(_) => return Err(HistoryError::Integrity("invalid accounting head".into())),
            };
            snapshot.tx.commit().await?;
            Ok(result)
        })
        .await
    }
    pub async fn wait_changed(&self, after: HistoryCut) -> Result<HistoryCut> {
        self.run(move |reader| async move {
            let after = reader.inner.codec.through(&after)?;
            let mut changed = reader.inner.store.changed.subscribe();
            let mut poll = tokio::time::interval(std::time::Duration::from_millis(50));
            loop {
                let snapshot = reader.snapshot().await?;
                let head = snapshot.head;
                snapshot.tx.commit().await?;
                if after > head {
                    return Err(HistoryError::InvalidCursor);
                }
                if head > after {
                    return reader.inner.codec.cut(head);
                }
                if reader.inner.store.read_only {
                    // Cold readers can observe a writer in another process. Poll only while an
                    // explicit change request is outstanding; there is no extra store task.
                    poll.tick().await;
                } else {
                    if !reader
                        .inner
                        .store
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .accepting
                    {
                        return Err(HistoryError::Closed);
                    }
                    changed.changed().await.map_err(|_| HistoryError::Closed)?;
                }
            }
        })
        .await
    }
    pub async fn review_finish_call(
        &self,
        turn_id: String,
        cut: Option<HistoryCut>,
        demand: HistoryDemand,
    ) -> Result<Option<HistoryEventDetail>> {
        self.run(move |reader| async move {
            demand.validate()?;
            if turn_id.is_empty() {
                return Err(HistoryError::InvalidDemand(
                    "empty review Turn identity".into(),
                ));
            }
            let snapshot = reader.snapshot().await?;
            let through = match cut {
                Some(cut) => reader.inner.codec.through(&cut)?,
                None => snapshot.head,
            };
            if through > snapshot.head {
                return Err(HistoryError::InvalidCursor);
            }
            let pending = snapshot
                .pending
                .finish(&turn_id, through)
                .map(|event| Record::from_event(&event.event));
            let stored = db::review_finish(&snapshot.tx, &turn_id, through).await?;
            let event = match (pending, stored) {
                (Some(pending), Some(stored)) if pending.header.seq > stored.header.seq => {
                    Some(pending)
                }
                (Some(_), Some(stored)) => Some(stored),
                (pending, stored) => pending.or(stored),
            };
            let detail = match event {
                None => None,
                Some(event) => Some(reader.detail(&snapshot, event).await?),
            };
            if !demand.fits(&detail)? {
                return Err(HistoryError::InvalidDemand(
                    "review detail exceeds budget".into(),
                ));
            }
            snapshot.tx.commit().await?;
            Ok(detail)
        })
        .await
    }
    pub fn request_close(&self) {
        let mut state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closed = true;
        self.inner.tasks.close();
        self.inner.cancel.cancel();
    }
    pub async fn close(&self) {
        self.request_close();
        self.inner.tasks.wait().await;
    }
}

/// The whole wire envelope counts against the demand, including cut and continuation.
/// Borrow the actual page so diagnostics never clone bodies or member collections.
fn observe_page(query: &Query, page: &HistoryTimelinePage, examined: usize) -> Result<()> {
    if !tracing::enabled!(target: "conversation_work", tracing::Level::DEBUG) {
        return Ok(());
    }
    let (bytes, scope) = match query {
        Query::Group(group_id) => {
            #[derive(serde::Serialize)]
            #[serde(rename_all = "camelCase")]
            struct GroupPage<'a> {
                cut: &'a HistoryCut,
                group_id: &'a str,
                members: &'a [HistoryTimelineEntry],
                next: &'a Option<String>,
            }
            (
                serde_json::to_vec(&GroupPage {
                    cut: &page.cut,
                    group_id,
                    members: &page.entries,
                    next: &page.next,
                })?
                .len(),
                "group",
            )
        }
        Query::Main => (serde_json::to_vec(page)?.len(), "main"),
        _ => (serde_json::to_vec(page)?.len(), "business"),
    };
    tracing::debug!(target: "conversation_work",
        timeline_examined_anchors = examined,
        timeline_returned_bytes = bytes,
        timeline_returned_rows = page.entries.len(), scope,
        "history page read"
    );
    Ok(())
}

fn fits_entries(
    demand: HistoryDemand,
    empty_page: &impl serde::Serialize,
    bytes: usize,
    count: usize,
) -> Result<bool> {
    Ok(
        serde_json::to_vec(empty_page)?.len() + bytes + count.saturating_sub(1)
            <= demand.max_bytes as usize,
    )
}

async fn resolve_event(snapshot: &Snapshot, id: &str) -> Result<Option<Record>> {
    if let Some(accepted) = snapshot.pending.event(id) {
        return Ok(Some(Record::from_event(&accepted.event)));
    }
    Ok(db::event(&snapshot.tx, id)
        .await?
        .filter(|event| event.header.seq <= snapshot.head))
}
async fn resolve_body(snapshot: &Snapshot, id: &str) -> Result<Option<Body>> {
    if let Some((seq, ordinal)) = snapshot.pending.bodies.get(id) {
        return Ok(Some(
            snapshot.pending.events[seq].body_headers[*ordinal].clone(),
        ));
    }
    db::body(&snapshot.tx, id).await
}
async fn latest_head(snapshot: &Snapshot, row: &str, cut: u64) -> Result<Option<Record>> {
    let pending = snapshot
        .pending
        .head(row, cut)
        .map(|accepted| Record::from_event(&accepted.event));
    let database = db::head(&snapshot.tx, row, cut).await?;
    Ok(match (pending, database) {
        (Some(pending), Some(database)) if pending.header.seq > database.header.seq => {
            Some(pending)
        }
        (Some(_), Some(database)) => Some(database),
        (pending, database) => pending.or(database),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn live_cut_uses_the_admitted_head_without_database_access() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            directory.path().join("history.sqlite"),
            "ram-cut",
            HistoryLimits::default(),
        )
        .await?;
        store
            .accept_batch(&[HistoryEvent::new("first", HistoryEventKind::RunStarted, 1)])
            .await?;
        let reader = store.reader();
        store.inner.reader.clone().close().await?;
        let (cut, head) = reader.capture_position().await?;
        assert_eq!(head, 1);
        assert_eq!(reader.capture().await?, cut);
        assert_eq!(reader.head().await?, 1);
        reader.close().await;
        assert!(matches!(
            reader.capture_position().await,
            Err(HistoryError::Closed)
        ));
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn committed_pending_root_stays_readable_and_retains_its_capacity_until_query_finishes()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            directory.path().join("history.sqlite"),
            "handoff",
            HistoryLimits {
                pending_events: 1,
                pending_bytes: 65_536,
            },
        )
        .await?;
        let event = HistoryEvent::new("first", HistoryEventKind::RunStarted, 1);
        store.accept_batch(&[event]).await?;
        let reader = store.reader();
        let snapshot = reader.snapshot().await?;
        store.flush().await?;
        assert!(store.inner.state.lock().unwrap().pending.events.is_empty());
        let status = store.status();
        assert_eq!(status.pending_events, 0, "COMMIT has cleared the save debt");
        assert_eq!(status.pending_bytes, 0);
        assert_eq!(status.retained_events, 1, "the old query still owns RAM");
        assert!(status.retained_bytes > 0);
        assert!(matches!(
            store
                .accept_batch(&[HistoryEvent::new("second", HistoryEventKind::RunStarted, 2)])
                .await,
            Err(HistoryError::Capacity)
        ));
        assert_eq!(
            resolve_event(&snapshot, "first").await?.unwrap().header.seq,
            1
        );
        drop(snapshot);
        assert_eq!(store.status().retained_events, 0);
        assert_eq!(store.status().retained_bytes, 0);
        store
            .accept_batch(&[HistoryEvent::new("second", HistoryEventKind::RunStarted, 2)])
            .await?;
        assert_eq!(
            reader
                .events_page(
                    HistoryEventsQuery::AllEvents,
                    None,
                    None,
                    HistoryDemand::default()
                )
                .await?
                .entries
                .len(),
            2
        );
        reader.close().await;
        store.close().await?;
        Ok(())
    }
}
