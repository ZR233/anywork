use std::{
    collections::BTreeSet,
    future::Future,
    sync::{Arc, Mutex},
};

use sea_orm::{DatabaseTransaction, TransactionTrait};
use sha2::{Digest, Sha256};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::Instrument;

use super::{
    body::decode_business_head_from_record,
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

    pub async fn head(&self) -> Result<u64> {
        self.capture_position().await.map(|(_, head)| head)
    }

    pub async fn timeline_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let (cut, through, mut upper_seq, mut upper_boundary_seq) =
                if let Some(cursor_token) = cursor {
                    match reader.inner.codec.decode(&cursor_token)? {
                        Token::TimelinePage {
                            cut: saved,
                            upper_seq,
                            upper_boundary_seq,
                        } if cut.as_ref().is_none_or(|c| c == &saved) => {
                            let through = reader.inner.codec.through(&saved)?;
                            if through > snapshot.head
                                || upper_seq > through
                                || upper_boundary_seq
                                    .is_some_and(|bound| bound > through || bound <= upper_seq)
                            {
                                return Err(HistoryError::InvalidCursor);
                            }
                            (saved, through, upper_seq, upper_boundary_seq)
                        }
                        _ => return Err(HistoryError::InvalidCursor),
                    }
                } else {
                    let saved = match cut {
                        Some(cut) => cut,
                        None => reader.inner.codec.cut(snapshot.head)?,
                    };
                    let through = reader.inner.codec.through(&saved)?;
                    if through > snapshot.head {
                        return Err(HistoryError::InvalidCursor);
                    }
                    (saved, through, through, None)
                };

            let max_rows = demand.max_rows as usize;
            let mut entries: Vec<HistoryTimelineEntry> = Vec::new();
            let mut examined: u64 = 0;
            let mut next_cursor: Option<String> = None;
            let mut oldest_returned_seq: Option<u64> = None;

            'outer: while entries.len() < max_rows && upper_seq > 0 {
                let remaining_slots = max_rows - entries.len();
                let batch_size = remaining_slots.min(64);
                let fetch_limit = batch_size + 1;
                let upper_excl = upper_boundary_seq.unwrap_or_else(|| through.saturating_add(1));
                let include_tail_end = upper_boundary_seq.is_none();
                let direct_rows = merged_direct_entries(
                    &snapshot,
                    upper_seq,
                    upper_excl,
                    include_tail_end,
                    fetch_limit,
                )
                .await?;
                let exhausted_all_direct = direct_rows.len() < fetch_limit;
                let process_count = direct_rows.len().min(batch_size);

                for (i, row) in direct_rows.into_iter().take(process_count).enumerate() {
                    examined += 1;
                    let entry_seq = row.record.seq;
                    let has_more_below = i + 1 < process_count || !exhausted_all_direct;
                    let candidate_next = if has_more_below {
                        Some(reader.inner.codec.encode(Token::TimelinePage {
                            cut: cut.clone(),
                            upper_seq: entry_seq.saturating_sub(1),
                            upper_boundary_seq: Some(entry_seq),
                        })?)
                    } else {
                        None
                    };
                    entries.push(HistoryTimelineEntry {
                        event: row.record,
                        has_folded_after: row.has_folded_after,
                        tail_folded_ended_at: row.tail_folded_ended_at,
                    });
                    let probe = HistoryTimelinePage {
                        cut: cut.clone(),
                        entries: entries.clone(),
                        has_folded_before_oldest: false,
                        next: candidate_next.clone(),
                    };
                    if !demand.fits(&probe)? {
                        entries.pop();
                        if entries.is_empty() {
                            return Err(HistoryError::InvalidDemand(
                                "single timeline entry exceeds byte demand".into(),
                            ));
                        }
                        next_cursor = Some(reader.inner.codec.encode(Token::TimelinePage {
                            cut: cut.clone(),
                            upper_seq,
                            upper_boundary_seq,
                        })?);
                        break 'outer;
                    }
                    oldest_returned_seq = Some(entry_seq);
                    upper_boundary_seq = Some(entry_seq);
                    upper_seq = entry_seq.saturating_sub(1);
                    if candidate_next.is_none() {
                        next_cursor = None;
                        break 'outer;
                    }
                    if entries.len() >= max_rows {
                        next_cursor = candidate_next;
                        break 'outer;
                    }
                }

                if exhausted_all_direct {
                    upper_seq = 0;
                }
            }

            let has_folded_before_oldest = if next_cursor.is_none() {
                let oldest_excl = oldest_returned_seq
                    .or(upper_boundary_seq)
                    .unwrap_or_else(|| through.saturating_add(1));
                if oldest_excl > 1 {
                    snapshot.pending.has_work_in_range(0, oldest_excl)
                        || db::has_work_in_range(&snapshot.tx, 0, oldest_excl).await?
                } else {
                    false
                }
            } else {
                false
            };

            snapshot.tx.commit().await?;
            let page = HistoryTimelinePage {
                cut,
                entries,
                has_folded_before_oldest,
                next: next_cursor,
            };
            let returned_bytes = serde_json::to_vec(&page)?.len() as u64;
            tracing::debug!(
                target: "conversation_work",
                timeline_examined_anchors = examined,
                timeline_returned_bytes = returned_bytes,
                through,
                "history timeline page read"
            );
            Ok(page)
        })
        .await
    }

    pub async fn work_range_page(
        &self,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryWorkRangePage> {
        if before_seq == Some(0) {
            return Err(HistoryError::InvalidDemand(
                "work_range_page before_seq must be positive".into(),
            ));
        }
        if let (Some(after), Some(before)) = (after_seq, before_seq)
            && after >= before
        {
            return Err(HistoryError::InvalidDemand(
                "work_range_page after_seq must be less than before_seq".into(),
            ));
        }
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let (cut, through, cur_after) = if let Some(cursor_token) = cursor {
                match reader.inner.codec.decode(&cursor_token)? {
                    Token::WorkRangePage {
                        cut: saved,
                        after_seq: saved_after,
                        before_seq: saved_before,
                        after,
                    } if saved_after == after_seq
                        && saved_before == before_seq
                        && cut.as_ref().is_none_or(|c| c == &saved) =>
                    {
                        let through = reader.inner.codec.through(&saved)?;
                        let min_excl = after_seq.unwrap_or(0);
                        let max_incl =
                            before_seq.map_or(through, |b| b.saturating_sub(1).min(through));
                        if through > snapshot.head || after < min_excl || after > max_incl {
                            return Err(HistoryError::InvalidCursor);
                        }
                        (saved, through, after)
                    }
                    _ => return Err(HistoryError::InvalidCursor),
                }
            } else {
                let saved = match cut {
                    Some(cut) => cut,
                    None => reader.inner.codec.cut(snapshot.head)?,
                };
                let through = reader.inner.codec.through(&saved)?;
                if through > snapshot.head {
                    return Err(HistoryError::InvalidCursor);
                }
                (saved, through, after_seq.unwrap_or(0))
            };

            let max_incl = before_seq.map_or(through, |b| b.saturating_sub(1).min(through));
            let fetch_limit = (demand.max_rows as usize) + 1;
            let database =
                db::work_range_events(&snapshot.tx, cur_after, max_incl, fetch_limit).await?;
            let pending = snapshot
                .pending
                .work_range_events(cur_after, max_incl, fetch_limit);
            let merged = db::dedup_records_asc(database, pending, fetch_limit);
            snapshot.tx.commit().await?;

            let mut events = Vec::new();
            let mut last_seq = cur_after;
            let mut has_more = false;
            for (idx, row) in merged.iter().enumerate() {
                if events.len() >= demand.max_rows as usize {
                    has_more = true;
                    break;
                }
                let might_have_more = idx + 1 < merged.len();
                let candidate_next = if might_have_more {
                    Some(reader.inner.codec.encode(Token::WorkRangePage {
                        cut: cut.clone(),
                        after_seq,
                        before_seq,
                        after: row.record.seq,
                    })?)
                } else {
                    None
                };
                events.push(row.record.clone());
                let probe = HistoryWorkRangePage {
                    cut: cut.clone(),
                    after_seq,
                    before_seq,
                    events: events.clone(),
                    next: candidate_next,
                };
                if !demand.fits(&probe)? {
                    events.pop();
                    if events.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "single work event exceeds byte demand".into(),
                        ));
                    }
                    has_more = true;
                    break;
                }
                last_seq = row.record.seq;
            }
            let next = if has_more {
                Some(reader.inner.codec.encode(Token::WorkRangePage {
                    cut: cut.clone(),
                    after_seq,
                    before_seq,
                    after: last_seq,
                })?)
            } else {
                None
            };
            let page = HistoryWorkRangePage {
                cut,
                after_seq,
                before_seq,
                events,
                next,
            };
            let returned_bytes = serde_json::to_vec(&page)?.len() as u64;
            tracing::debug!(
                target: "conversation_work",
                timeline_returned_bytes = returned_bytes,
                "history work_range_page read"
            );
            Ok(page)
        })
        .await
    }

    pub async fn turns_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBusinessPage> {
        self.run(move |reader| async move {
            reader
                .business_rows(HistoryBusinessRowScope::Turn, cut, cursor, demand)
                .await
        })
        .await
    }

    pub async fn costs_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBusinessPage> {
        self.run(move |reader| async move {
            reader
                .business_rows(HistoryBusinessRowScope::Cost, cut, cursor, demand)
                .await
        })
        .await
    }

    async fn business_rows(
        &self,
        scope: HistoryBusinessRowScope,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBusinessPage> {
        demand.validate()?;
        let snapshot = self.snapshot().await?;
        let query = Query::BusinessRows(scope);
        let (cut, through, before) = self.page_cut(&query, cut, cursor, snapshot.head)?;
        let fetch_limit = (demand.max_rows as usize) + 1;

        let db_anchors =
            db::business_anchors(&snapshot.tx, scope, through, before, fetch_limit).await?;
        let mut seen_keys: BTreeSet<String> = db_anchors.iter().map(|(k, _)| k.clone()).collect();
        let pending_anchors =
            snapshot
                .pending
                .business_anchors(scope, through, before, fetch_limit, &mut seen_keys);

        let mut anchors: Vec<(String, u64)> = db_anchors;
        for accepted in pending_anchors {
            if let Some(key) = &accepted.event.row_key {
                anchors.push((key.clone(), accepted.event.seq));
            }
        }
        anchors.sort_by_key(|a| std::cmp::Reverse(a.1));
        anchors.truncate(fetch_limit);

        let mut entries = Vec::new();
        let mut last_anchor_seq: Option<u64> = None;
        let mut has_more = false;
        let mut examined: u64 = 0;

        for (idx, (row_key, anchor_seq)) in anchors.iter().enumerate() {
            if entries.len() >= demand.max_rows as usize {
                has_more = true;
                break;
            }
            examined += 1;
            let head_rec = resolve_row_head(&snapshot, row_key, through)
                .await?
                .ok_or_else(|| {
                    HistoryError::Integrity(format!("anchor row_key {row_key} has no head"))
                })?;
            let head = decode_business_head_from_record(&head_rec)?;
            let might_have_more = idx + 1 < anchors.len();
            let candidate_next = if might_have_more {
                Some(self.next(&cut, &query, *anchor_seq)?)
            } else {
                None
            };
            entries.push(HistoryBusinessRowEntry {
                row_key: row_key.clone(),
                anchor_seq: *anchor_seq,
                head_seq: head_rec.seq,
                head,
            });
            let probe = HistoryBusinessPage {
                cut: cut.clone(),
                entries: entries.clone(),
                next: candidate_next,
            };
            if !demand.fits(&probe)? {
                entries.pop();
                if entries.is_empty() {
                    return Err(HistoryError::InvalidDemand(
                        "single business row exceeds byte demand".into(),
                    ));
                }
                has_more = true;
                break;
            }
            last_anchor_seq = Some(*anchor_seq);
        }
        snapshot.tx.commit().await?;

        let next = if has_more {
            last_anchor_seq
                .map(|seq| self.next(&cut, &query, seq))
                .transpose()?
        } else {
            None
        };
        let page = HistoryBusinessPage { cut, entries, next };
        let returned_bytes = serde_json::to_vec(&page)?.len() as u64;
        tracing::debug!(
            target: "conversation_work",
            timeline_examined_anchors = examined,
            timeline_returned_bytes = returned_bytes,
            "history business rows page read"
        );
        Ok(page)
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
        if before.is_some_and(|b| b > through + 1) {
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

    pub async fn events_page(
        &self,
        query: HistoryEventsQuery,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryEventsPage> {
        validate::query(&query)?;
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let token_query = Query::Events(query.clone());
            let (cut, through, before) =
                reader.page_cut(&token_query, cut, cursor, snapshot.head)?;
            let max_incl = before.map_or(through, |b| b.saturating_sub(1).min(through));
            let fetch_limit = (demand.max_rows as usize) + 1;
            let database =
                db::events_filtered(&snapshot.tx, &query, 0, max_incl, false, fetch_limit).await?;
            let pending = snapshot
                .pending
                .events_matching(&query, 0, max_incl, false, fetch_limit);
            let merged = db::dedup_records_desc(database, pending, fetch_limit);
            snapshot.tx.commit().await?;

            let mut entries = Vec::new();
            let mut last_seq = None;
            let mut has_more = false;
            for (idx, row) in merged.iter().enumerate() {
                if entries.len() >= demand.max_rows as usize {
                    has_more = true;
                    break;
                }
                let might_have_more = idx + 1 < merged.len();
                let candidate_next = if might_have_more {
                    Some(reader.next(&cut, &token_query, row.record.seq)?)
                } else {
                    None
                };
                entries.push(row.record.clone());
                let probe = HistoryEventsPage {
                    cut: cut.clone(),
                    entries: entries.clone(),
                    next: candidate_next,
                };
                if !demand.fits(&probe)? {
                    entries.pop();
                    if entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "single history event exceeds byte demand".into(),
                        ));
                    }
                    has_more = true;
                    break;
                }
                last_seq = Some(row.record.seq);
            }
            let next = if has_more {
                last_seq
                    .map(|seq| reader.next(&cut, &token_query, seq))
                    .transpose()?
            } else {
                None
            };
            Ok(HistoryEventsPage { cut, entries, next })
        })
        .await
    }

    pub(crate) async fn events_window(
        &self,
        query: HistoryEventsQuery,
        through: Option<u64>,
        pivot: Option<u64>,
        ascending: bool,
        demand: HistoryDemand,
    ) -> Result<(u64, Vec<HistoryEventRecord>, bool)> {
        validate::query(&query)?;
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let ceiling = match through {
                Some(through) => {
                    if through > snapshot.head {
                        return Err(HistoryError::InvalidCursor);
                    }
                    through
                }
                None => snapshot.head,
            };
            let (min_excl, max_incl) = if ascending {
                (pivot.unwrap_or(0), ceiling)
            } else {
                let max_incl = match pivot {
                    Some(0) => {
                        snapshot.tx.commit().await?;
                        return Ok((ceiling, Vec::new(), false));
                    }
                    Some(pivot) => pivot.saturating_sub(1).min(ceiling),
                    None => ceiling,
                };
                (0, max_incl)
            };
            let fetch_limit = (demand.max_rows as usize) + 1;
            let database = db::events_filtered(
                &snapshot.tx,
                &query,
                min_excl,
                max_incl,
                ascending,
                fetch_limit,
            )
            .await?;
            let pending = snapshot.pending.events_matching(
                &query,
                min_excl,
                max_incl,
                ascending,
                fetch_limit,
            );
            let merged = if ascending {
                db::dedup_records_asc(database, pending, fetch_limit)
            } else {
                db::dedup_records_desc(database, pending, fetch_limit)
            };
            snapshot.tx.commit().await?;

            let mut entries = Vec::new();
            let mut has_more = false;
            for (idx, row) in merged.iter().enumerate() {
                if entries.len() >= demand.max_rows as usize {
                    has_more = true;
                    break;
                }
                entries.push(row.record.clone());
                if !demand.fits(&entries)? {
                    entries.pop();
                    if entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "single history event exceeds window byte demand".into(),
                        ));
                    }
                    has_more = true;
                    break;
                }
                if idx + 1 < merged.len() && entries.len() == demand.max_rows as usize {
                    has_more = true;
                    break;
                }
            }
            if !has_more && merged.len() > entries.len() {
                has_more = true;
            }
            Ok((ceiling, entries, has_more))
        })
        .await
    }

    pub async fn read_event(
        &self,
        event_id: String,
        demand: HistoryDemand,
    ) -> Result<HistoryEventRecord> {
        if event_id.is_empty() {
            return Err(HistoryError::InvalidDemand("empty event identity".into()));
        }
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let found = if let Some(accepted) = snapshot.pending.event(&event_id) {
                if accepted.event.seq <= snapshot.head {
                    Some(Record::from_event(&accepted.event))
                } else {
                    None
                }
            } else {
                None
            };
            let found = match found {
                Some(rec) => rec,
                None => db::event(&snapshot.tx, &event_id)
                    .await?
                    .ok_or_else(|| HistoryError::NotFound(event_id.clone()))?,
            };
            snapshot.tx.commit().await?;
            if !demand.fits(&found.record)? {
                return Err(HistoryError::InvalidDemand(
                    "history event exceeds byte demand".into(),
                ));
            }
            Ok(found.record)
        })
        .await
    }

    pub async fn original_for_entity(
        &self,
        entity_id: String,
        cut: Option<HistoryCut>,
        demand: HistoryDemand,
    ) -> Result<Option<HistoryEventRecord>> {
        if entity_id.is_empty() {
            return Err(HistoryError::InvalidDemand("empty entity identity".into()));
        }
        self.run(move |reader| async move {
            demand.validate()?;
            let snapshot = reader.snapshot().await?;
            let through = match cut {
                Some(cut) => {
                    let pos = reader.inner.codec.through(&cut)?;
                    if pos > snapshot.head {
                        return Err(HistoryError::InvalidCursor);
                    }
                    pos
                }
                None => snapshot.head,
            };
            let pending_rec = snapshot
                .pending
                .original_by_entity(&entity_id, through)
                .map(|accepted| Record::from_event(&accepted.event));
            let rec = match pending_rec {
                Some(rec) => Some(rec),
                None => db::original_by_entity(&snapshot.tx, &entity_id, through).await?,
            };
            snapshot.tx.commit().await?;
            if let Some(rec) = rec {
                if !demand.fits(&rec.record)? {
                    return Err(HistoryError::InvalidDemand(
                        "original history event exceeds byte demand".into(),
                    ));
                }
                Ok(Some(rec.record))
            } else {
                Ok(None)
            }
        })
        .await
    }

    pub async fn latest_row(
        &self,
        row_key: String,
        cut: Option<HistoryCut>,
    ) -> Result<Option<HistoryBusinessRowEntry>> {
        if row_key.is_empty() {
            return Err(HistoryError::InvalidDemand("empty row_key".into()));
        }
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            let through = match cut {
                Some(cut) => {
                    let pos = reader.inner.codec.through(&cut)?;
                    if pos > snapshot.head {
                        return Err(HistoryError::InvalidCursor);
                    }
                    pos
                }
                None => snapshot.head,
            };
            let Some(head_rec) = resolve_row_head(&snapshot, &row_key, through).await? else {
                snapshot.tx.commit().await?;
                return Ok(None);
            };
            let anchor_seq = if let Some(&seq) = snapshot.pending.anchors.get(&row_key)
                && seq <= through
            {
                seq
            } else if let Some(anchor) = db::anchor(&snapshot.tx, &row_key).await? {
                anchor.record.seq
            } else {
                head_rec.seq
            };
            snapshot.tx.commit().await?;
            let head = decode_business_head_from_record(&head_rec)?;
            Ok(Some(HistoryBusinessRowEntry {
                row_key,
                anchor_seq,
                head_seq: head_rec.seq,
                head,
            }))
        })
        .await
    }

    pub async fn list_bodies(
        &self,
        event_id: String,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBodyPage> {
        if event_id.is_empty() {
            return Err(HistoryError::InvalidDemand("empty event identity".into()));
        }
        self.run(move |reader| async move {
            demand.validate()?;
            let after = if let Some(cursor_token) = cursor {
                match reader.inner.codec.decode(&cursor_token)? {
                    Token::Bodies {
                        event_id: saved,
                        after,
                    } if saved == event_id => Some(after),
                    _ => return Err(HistoryError::InvalidCursor),
                }
            } else {
                None
            };
            let snapshot = reader.snapshot().await?;
            let db_id = reader.database_id();
            let fetch_limit = (demand.max_rows as usize) + 1;
            let all_bodies = if let Some(accepted) = snapshot.pending.event(&event_id) {
                accepted
                    .body_headers
                    .iter()
                    .filter(|body| after.is_none_or(|a| body.ordinal > a))
                    .take(fetch_limit)
                    .cloned()
                    .collect()
            } else {
                if db::event(&snapshot.tx, &event_id).await?.is_none() {
                    return Err(HistoryError::NotFound(event_id));
                }
                db::bodies(&snapshot.tx, &event_id, after, fetch_limit).await?
            };
            snapshot.tx.commit().await?;

            let mut entries = Vec::new();
            let mut last_ordinal = after;
            let mut has_more = false;
            for (idx, body) in all_bodies.iter().enumerate() {
                if entries.len() >= demand.max_rows as usize {
                    has_more = true;
                    break;
                }
                let might_have_more = idx + 1 < all_bodies.len();
                let candidate_next = if might_have_more {
                    Some(reader.inner.codec.encode(Token::Bodies {
                        event_id: event_id.clone(),
                        after: body.ordinal,
                    })?)
                } else {
                    None
                };
                entries.push(body.entry(db_id));
                let probe = HistoryBodyPage {
                    owner_event_id: event_id.clone(),
                    entries: entries.clone(),
                    next: candidate_next,
                };
                if !demand.fits(&probe)? {
                    entries.pop();
                    if entries.is_empty() {
                        return Err(HistoryError::InvalidDemand(
                            "single body entry exceeds byte demand".into(),
                        ));
                    }
                    has_more = true;
                    break;
                }
                last_ordinal = Some(body.ordinal);
            }
            let next = if has_more {
                last_ordinal
                    .map(|ord| {
                        reader.inner.codec.encode(Token::Bodies {
                            event_id: event_id.clone(),
                            after: ord,
                        })
                    })
                    .transpose()?
            } else {
                None
            };
            Ok(HistoryBodyPage {
                owner_event_id: event_id,
                entries,
                next,
            })
        })
        .await
    }

    pub async fn read_body(
        &self,
        reference: HistoryEventBodyRef,
        offset: u64,
        length: u32,
    ) -> Result<HistoryBodyWindow> {
        if reference.database_id != self.database_id() || reference.byte_start != 0 {
            return Err(HistoryError::InvalidCursor);
        }
        if length == 0 || length as usize > BODY_CHUNK_BYTES {
            return Err(HistoryError::InvalidDemand(
                "body read length must be 1..=65536".into(),
            ));
        }
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            if let Some((accepted, header, index)) = snapshot.pending.body(&reference.body_id) {
                validate_body_ref(&reference, header)?;
                if offset > header.length {
                    return Err(HistoryError::InvalidDemand(
                        "body read offset exceeds length".into(),
                    ));
                }
                let raw = &accepted.event.bodies[index].bytes;
                if Sha256::digest(raw).as_slice() != header.digest.as_slice() {
                    return Err(HistoryError::Integrity(
                        "pending body digest mismatch".into(),
                    ));
                }
                let end = offset
                    .saturating_add(length.min(BODY_CHUNK_BYTES as u32) as u64)
                    .min(header.length) as usize;
                let bytes = raw[offset as usize..end].to_vec();
                tracing::debug!(
                    target: "conversation_work",
                    history_body_bytes_read = bytes.len() as u64,
                    history_body_returned_bytes = bytes.len() as u64,
                    "history pending body window read"
                );
                snapshot.tx.commit().await?;
                return Ok(HistoryBodyWindow {
                    offset,
                    bytes,
                    total_length: header.length,
                    media_type: header.media_type.clone(),
                });
            }
            let body = db::body(&snapshot.tx, &reference.body_id)
                .await?
                .ok_or_else(|| HistoryError::NotFound(reference.body_id.clone()))?;
            validate_body_ref(&reference, &body)?;
            let bytes = db::window(&snapshot.tx, &body, offset, length).await?;
            snapshot.tx.commit().await?;
            Ok(HistoryBodyWindow {
                offset,
                bytes,
                total_length: body.length,
                media_type: body.media_type,
            })
        })
        .await
    }

    pub async fn verify_body(&self, reference: HistoryEventBodyRef) -> Result<()> {
        if reference.database_id != self.database_id() || reference.byte_start != 0 {
            return Err(HistoryError::InvalidCursor);
        }
        self.run(move |reader| async move {
            let snapshot = reader.snapshot().await?;
            if let Some((accepted, header, index)) = snapshot.pending.body(&reference.body_id) {
                validate_body_ref(&reference, header)?;
                let raw = &accepted.event.bodies[index].bytes;
                if raw.len() as u64 != header.length
                    || Sha256::digest(raw).as_slice() != header.digest.as_slice()
                {
                    return Err(HistoryError::Integrity(
                        "pending body verification failed".into(),
                    ));
                }
                snapshot.tx.commit().await?;
                return Ok(());
            }
            let body = db::body(&snapshot.tx, &reference.body_id)
                .await?
                .ok_or_else(|| HistoryError::NotFound(reference.body_id.clone()))?;
            validate_body_ref(&reference, &body)?;
            let mut hasher = Sha256::new();
            let mut offset = 0u64;
            while offset < body.length {
                let bytes =
                    db::window(&snapshot.tx, &body, offset, BODY_CHUNK_BYTES as u32).await?;
                if bytes.is_empty() {
                    return Err(HistoryError::Integrity("body verify stopped early".into()));
                }
                hasher.update(&bytes);
                offset += bytes.len() as u64;
            }
            snapshot.tx.commit().await?;
            if hasher.finalize().as_slice() != body.digest.as_slice() {
                return Err(HistoryError::Integrity(
                    "stored body digest mismatch".into(),
                ));
            }
            Ok(())
        })
        .await
    }

    pub async fn accounting(
        &self,
        cut: Option<HistoryCut>,
    ) -> Result<Option<HistoryAccountingHead>> {
        let Some(entry) = self.latest_row("accounting:session".into(), cut).await? else {
            return Ok(None);
        };
        match entry.head {
            HistoryBusinessRowHead::Accounting(head) => Ok(Some(head)),
            _ => Err(HistoryError::Integrity(
                "accounting row head has wrong variant".into(),
            )),
        }
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

    pub fn request_close(&self) {
        {
            let mut reader = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            reader.closed = true;
        }
        self.inner.cancel.cancel();
        self.inner.tasks.close();
    }

    pub async fn close(&self) {
        self.request_close();
        self.inner.tasks.wait().await;
    }
}

async fn resolve_row_head(
    snapshot: &Snapshot,
    row_key: &str,
    through: u64,
) -> Result<Option<HistoryEventRecord>> {
    let pending = snapshot.pending.head(row_key, through);
    let database = db::head(&snapshot.tx, row_key, through).await?;
    Ok(match (pending, database) {
        (Some(p), Some(d)) => {
            if p.event.seq >= d.record.seq {
                Some(p.event.to_record())
            } else {
                Some(d.record)
            }
        }
        (Some(p), None) => Some(p.event.to_record()),
        (None, Some(d)) => Some(d.record),
        (None, None) => None,
    })
}

struct DirectEntryCandidate {
    record: HistoryEventRecord,
    has_folded_after: bool,
    tail_folded_ended_at: Option<i64>,
}

async fn merged_direct_entries(
    snapshot: &Snapshot,
    upper_seq: u64,
    upper_excl: u64,
    include_tail_end: bool,
    limit: usize,
) -> Result<Vec<DirectEntryCandidate>> {
    if upper_seq == 0 || limit == 0 {
        return Ok(Vec::new());
    }
    let pending_bounds = snapshot.pending.boundaries_at_or_before(upper_seq, limit);
    let db_rows = db::direct_timeline_entries_at_or_before(
        &snapshot.tx,
        upper_seq,
        upper_excl,
        include_tail_end,
        limit,
    )
    .await?;
    if pending_bounds.is_empty() && snapshot.pending.events.is_empty() {
        return Ok(db_rows
            .into_iter()
            .map(|row| DirectEntryCandidate {
                record: row.record.record,
                has_folded_after: row.has_folded_after,
                tail_folded_ended_at: row.tail_folded_ended_at,
            })
            .collect());
    }

    let mut merged: Vec<DirectEntryCandidate> = db_rows
        .into_iter()
        .map(|row| DirectEntryCandidate {
            record: row.record.record,
            has_folded_after: row.has_folded_after,
            tail_folded_ended_at: row.tail_folded_ended_at,
        })
        .collect();
    for entry in pending_bounds {
        let rec = entry.event.to_record();
        if !merged.iter().any(|existing| existing.record.seq == rec.seq) {
            merged.push(DirectEntryCandidate {
                record: rec,
                has_folded_after: false,
                tail_folded_ended_at: None,
            });
        }
    }
    merged.sort_by_key(|a| std::cmp::Reverse(a.record.seq));
    merged.truncate(limit);

    let mut newer_seq = upper_excl;
    for (idx, item) in merged.iter_mut().enumerate() {
        let pending_has_work = snapshot
            .pending
            .has_work_in_range(item.record.seq, newer_seq);
        if pending_has_work {
            item.has_folded_after = true;
        }
        if include_tail_end && idx == 0 {
            if let Some(pending_tail) = snapshot
                .pending
                .latest_work_time_in_range(item.record.seq, newer_seq)
            {
                item.tail_folded_ended_at = Some(pending_tail);
            }
        } else {
            item.tail_folded_ended_at = None;
        }
        newer_seq = item.record.seq;
    }
    Ok(merged)
}

fn validate_body_ref(reference: &HistoryEventBodyRef, body: &Body) -> Result<()> {
    if body.owner != reference.owner_event_id
        || body.key != reference.body_key
        || reference.byte_start != 0
        || reference
            .byte_start
            .checked_add(reference.byte_length)
            .is_none_or(|end| end > body.length)
        || reference.byte_length != body.length
    {
        return Err(HistoryError::InvalidCursor);
    }
    Ok(())
}
