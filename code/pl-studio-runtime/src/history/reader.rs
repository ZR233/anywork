use std::{
    collections::BTreeMap,
    future::Future,
    sync::{Arc, Mutex},
};

use sea_orm::{DatabaseTransaction, TransactionTrait};
use sha2::{Digest, Sha256};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

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
    async fn run<T>(&self, future: impl Future<Output = Result<T>>) -> Result<T> {
        let (reader_task, store_task) = {
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
            (
                self.inner.tasks.token(),
                self.inner.store.operations.token(),
            )
        };
        let result = tokio::select! {
            biased;
            _ = self.inner.cancel.cancelled() => Err(HistoryError::Closed),
            _ = self.inner.store.cancel.cancelled() => Err(HistoryError::Closed),
            result = future => result,
        };
        drop((reader_task, store_task));
        result
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
        Ok(Snapshot { head, pending, tx })
    }
    pub async fn capture(&self) -> Result<HistoryCut> {
        self.run(async {
            let head = self
                .inner
                .store
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .head;
            self.inner.codec.cut(head)
        })
        .await
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
        self.run(self.rows(Query::Main, cut, cursor, demand)).await
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
        self.run(async {
            let page = self
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
    pub async fn costs_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.run(self.rows(Query::Rows("cost".into()), cut, cursor, demand))
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
        for (index, (anchor_seq, row_key)) in candidates.into_iter().rev().take(limit).enumerate() {
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
        self.run(async {
            demand.validate()?;
            validate::query(&query)?;
            let snapshot = self.snapshot().await?;
            let query = Query::Events(query);
            let (cut, through, before) = self.page_cut(&query, cut, cursor, snapshot.head)?;
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
                let detail = self.detail(&snapshot, event).await?;
                let previous_next = page.next.clone();
                page.next = if exhausted && index + 1 == candidate_count {
                    None
                } else {
                    Some(self.next(&page.cut, &query, seq)?)
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
        self.run(async {
            demand.validate()?;
            let snapshot = self.snapshot().await?;
            let event = resolve_event(&snapshot, &event_id)
                .await?
                .ok_or_else(|| HistoryError::NotFound(event_id))?;
            let detail = self.detail(&snapshot, event).await?;
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
    pub async fn list_bodies(
        &self,
        event_id: String,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBodyPage> {
        self.run(async {
            demand.validate()?;
            let after = match cursor {
                None => None,
                Some(cursor) => match self.inner.codec.decode(&cursor)? {
                    Token::Bodies {
                        event_id: saved,
                        after,
                    } if saved == event_id => Some(after),
                    _ => return Err(HistoryError::InvalidCursor),
                },
            };
            let snapshot = self.snapshot().await?;
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
                    Some(self.inner.codec.encode(Token::Bodies {
                        event_id: page.owner_event_id.clone(),
                        after: body.ordinal,
                    })?)
                };
                let entry = body.entry(&self.inner.store.database_id);
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
        self.run(async {
            if max_bytes == 0 || max_bytes as usize > BODY_CHUNK_BYTES {
                return Err(HistoryError::InvalidDemand(
                    "body window must be 1..65536 bytes".into(),
                ));
            }
            let snapshot = self.snapshot().await?;
            let body = self.authorize_body(&snapshot, &reference).await?;
            if offset > reference.byte_length {
                return Err(HistoryError::InvalidDemand(
                    "offset exceeds body slice".into(),
                ));
            }
            let length = (reference.byte_length - offset).min(max_bytes as u64) as usize;
            let start = reference.byte_start + offset;
            let bytes = if let Some((seq, ordinal)) = snapshot.pending.bodies.get(&body.id) {
                snapshot.pending.events[seq].event.bodies[*ordinal].bytes
                    [start as usize..start as usize + length]
                    .to_vec()
            } else {
                db::window(&snapshot.tx, &body, start, length).await?
            };
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
        self.run(async {
            let snapshot = self.snapshot().await?;
            let body = self.authorize_body(&snapshot, &reference).await?;
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
        self.run(async {
            let snapshot = self.snapshot().await?;
            let through = match cut {
                Some(cut) => self.inner.codec.through(&cut)?,
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
        self.run(async {
            let mut changed = self.inner.store.changed.subscribe();
            let after = self.inner.codec.through(&after)?;
            if after > *changed.borrow() {
                return Err(HistoryError::InvalidCursor);
            }
            loop {
                let head = *changed.borrow_and_update();
                if head > after {
                    return self.inner.codec.cut(head);
                }
                changed.changed().await.map_err(|_| HistoryError::Closed)?;
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
        self.run(async {
            demand.validate()?;
            if turn_id.is_empty() {
                return Err(HistoryError::InvalidDemand(
                    "empty review Turn identity".into(),
                ));
            }
            let snapshot = self.snapshot().await?;
            let through = match cut {
                Some(cut) => self.inner.codec.through(&cut)?,
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
                Some(event) => Some(self.detail(&snapshot, event).await?),
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
        assert_eq!(
            store.status().pending_events,
            1,
            "the old immutable root still owns its reservation"
        );
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
