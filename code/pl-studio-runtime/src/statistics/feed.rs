use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

use super::models::{
    StudioModelPerformanceEffortSummary, StudioModelPerformanceSample,
    StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
};

mod scope;
use scope::ReadScopeInner;
pub use scope::StatisticsReadScope;

const MAX_UNACKNOWLEDGED_PUBLICATIONS: usize = 2;
const MAX_OPEN_SCOPES: usize = 2;
const MAX_PAGE_ITEMS: u32 = 128;
const MAX_SOURCE_PAGE_BYTES: usize = 256 * 1024;

/// Immutable identity and status for one latest-value publication delivered to a feed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatisticsFeedHeader {
    pub owner_epoch: String,
    pub feed_id: String,
    /// Transport delivery identity; not a business or material revision.
    pub delivery_sequence: u64,
    pub publication_revision: u64,
    pub summaries_revision: u64,
    pub history_revision: u64,
    pub summary_count: u64,
    pub history_count: u64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
}

/// Summary-page item without its separately paged effort material.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatisticsSummary {
    pub account_id: String,
    pub account_display_name: String,
    pub model_id: String,
    pub sample_count: u64,
    pub completion_tokens: u64,
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
    pub effort_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatisticsSummaryPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    /// Number of bytes in the source-encoded page, not a wire or process-memory estimate.
    pub source_bytes: u64,
    pub items: Vec<StatisticsSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatisticsHistoryPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    /// Number of bytes in the source-encoded page, not a wire or process-memory estimate.
    pub source_bytes: u64,
    pub items: Vec<StudioModelPerformanceSample>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatisticsEffortPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub summary_index: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    /// Number of bytes in the source-encoded page, not a wire or process-memory estimate.
    pub source_bytes: u64,
    pub items: Vec<StudioModelPerformanceEffortSummary>,
}

/// An immutable runtime publication; only its status/revision header changes between updates.
#[derive(Debug)]
pub(crate) struct StatisticsPublication {
    owner_epoch: String,
    publication_revision: u64,
    summaries_revision: u64,
    history_revision: u64,
    summaries: Arc<Vec<StudioModelPerformanceSummary>>,
    history: Arc<Vec<StudioModelPerformanceSample>>,
    statistics_pending: bool,
    statistics_gap: bool,
    read_failed: bool,
}

/// Latest-value publisher owned by the existing model-performance owner.
#[derive(Clone)]
pub(crate) struct StatisticsPublisher {
    owner_epoch: String,
    latest: watch::Sender<Arc<StatisticsPublication>>,
}

impl StatisticsPublisher {
    pub(crate) fn new(owner_epoch: String) -> Self {
        let initial = Arc::new(StatisticsPublication {
            owner_epoch: owner_epoch.clone(),
            publication_revision: 0,
            summaries_revision: 0,
            history_revision: 0,
            summaries: Arc::new(Vec::new()),
            history: Arc::new(Vec::new()),
            statistics_pending: false,
            statistics_gap: false,
            read_failed: false,
        });
        let (latest, _) = watch::channel(initial);
        Self {
            owner_epoch,
            latest,
        }
    }

    /// Publishes the exact materials and flags already adopted by the owner.
    ///
    /// Unchanged material retains its `Arc` and revision. `send_replace` retains the latest
    /// publication even when no feed currently has a receiver.
    pub(crate) fn publish(&self, snapshot: &StudioModelPerformanceSnapshot) {
        let previous = self.latest.borrow().clone();
        let summaries_changed = previous.summaries.as_ref() != &snapshot.summaries;
        let history_changed = previous.history.as_ref() != &snapshot.history;
        let summaries = if summaries_changed {
            Arc::new(snapshot.summaries.clone())
        } else {
            Arc::clone(&previous.summaries)
        };
        let history = if history_changed {
            Arc::new(snapshot.history.clone())
        } else {
            Arc::clone(&previous.history)
        };
        let next = StatisticsPublication {
            owner_epoch: self.owner_epoch.clone(),
            publication_revision: snapshot.revision,
            summaries_revision: previous
                .summaries_revision
                .saturating_add(u64::from(summaries_changed)),
            history_revision: previous
                .history_revision
                .saturating_add(u64::from(history_changed)),
            summaries,
            history,
            statistics_pending: snapshot.statistics_pending,
            statistics_gap: snapshot.statistics_gap,
            read_failed: snapshot.read_failed,
        };
        let unchanged = previous.publication_revision == next.publication_revision
            && previous.summaries_revision == next.summaries_revision
            && previous.history_revision == next.history_revision
            && previous.statistics_pending == next.statistics_pending
            && previous.statistics_gap == next.statistics_gap
            && previous.read_failed == next.read_failed;
        if !unchanged {
            self.latest.send_replace(Arc::new(next));
        }
    }

    /// Publishes status-only owner changes without comparing or cloning retained material.
    pub(crate) fn publish_status(
        &self,
        publication_revision: u64,
        statistics_pending: bool,
        statistics_gap: bool,
        read_failed: bool,
    ) {
        let previous = self.latest.borrow().clone();
        let unchanged = previous.publication_revision == publication_revision
            && previous.statistics_pending == statistics_pending
            && previous.statistics_gap == statistics_gap
            && previous.read_failed == read_failed;
        if unchanged {
            return;
        }
        self.latest.send_replace(Arc::new(StatisticsPublication {
            owner_epoch: self.owner_epoch.clone(),
            publication_revision,
            summaries_revision: previous.summaries_revision,
            history_revision: previous.history_revision,
            summaries: Arc::clone(&previous.summaries),
            history: Arc::clone(&previous.history),
            statistics_pending,
            statistics_gap,
            read_failed,
        }));
    }

    pub(crate) fn subscribe(&self) -> StatisticsFeed {
        let id = crate::studio::new_id("statistics-feed");
        StatisticsFeed::new(id, self.owner_epoch.clone(), self.latest.subscribe())
    }
}

/// Typed failures from feed admission, scoped reads, and close.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum StatisticsError {
    #[error("statistics feed is closed")]
    Closed,
    #[error("statistics feed or scope identity does not match its source")]
    InvalidReference,
    #[error("statistics feed already has an in-flight next operation")]
    NextInFlight,
    #[error("statistics feed has no capacity for another unacknowledged publication")]
    PublicationCapacity,
    #[error("statistics feed has no capacity for another read scope")]
    ScopeCapacity,
    #[error("statistics page read is already in flight for this scope")]
    PageInFlight,
    #[error("statistics page limit must be between 1 and 128")]
    InvalidPageLimit,
    #[error("statistics page source encoding exceeds the 256 KiB capacity")]
    PageCapacity,
}

struct FeedState {
    closed: bool,
    next_in_flight: bool,
    next_delivery_sequence: u64,
    acknowledged_sequence: u64,
    last_publication_revision: Option<u64>,
    pending: VecDeque<(u64, Arc<StatisticsPublication>)>,
    scopes: BTreeMap<String, Arc<ReadScopeInner>>,
}

struct FeedInner {
    id: String,
    owner_epoch: String,
    receiver: tokio::sync::Mutex<watch::Receiver<Arc<StatisticsPublication>>>,
    state: Mutex<FeedState>,
    cancellation: CancellationToken,
    acknowledgement: Notify,
    changed: Notify,
    active_calls: std::sync::atomic::AtomicUsize,
}

/// One GUI statistics feed. Intermediate publications may be coalesced, but every returned frame
/// remains charged against the two-frame outstanding limit until the consumer acknowledges it.
#[derive(Clone)]
pub struct StatisticsFeed {
    inner: Arc<FeedInner>,
}

impl StatisticsFeed {
    fn new(
        id: String,
        owner_epoch: String,
        receiver: watch::Receiver<Arc<StatisticsPublication>>,
    ) -> Self {
        Self {
            inner: Arc::new(FeedInner {
                id,
                owner_epoch,
                receiver: tokio::sync::Mutex::new(receiver),
                state: Mutex::new(FeedState {
                    closed: false,
                    next_in_flight: false,
                    next_delivery_sequence: 0,
                    acknowledged_sequence: 0,
                    last_publication_revision: None,
                    pending: VecDeque::new(),
                    scopes: BTreeMap::new(),
                }),
                cancellation: CancellationToken::new(),
                acknowledgement: Notify::new(),
                changed: Notify::new(),
                active_calls: std::sync::atomic::AtomicUsize::new(0),
            }),
        }
    }

    /// Waits for the current publication or a later latest value.
    pub async fn next(&self) -> Result<Option<StatisticsFeedHeader>, StatisticsError> {
        let attempt = self.inner.begin_next()?;
        let mut receiver = self.inner.receiver.lock().await;
        loop {
            if self.inner.is_closed() {
                return Ok(None);
            }
            let publication = receiver.borrow_and_update().clone();
            let header = {
                let mut state = self.inner.lock_state();
                if state.closed {
                    return Ok(None);
                }
                if state.pending.len() < MAX_UNACKNOWLEDGED_PUBLICATIONS
                    && state.last_publication_revision != Some(publication.publication_revision)
                {
                    state.next_delivery_sequence = state.next_delivery_sequence.saturating_add(1);
                    let sequence = state.next_delivery_sequence;
                    state.last_publication_revision = Some(publication.publication_revision);
                    state
                        .pending
                        .push_back((sequence, Arc::clone(&publication)));
                    Some(header_from_publication(
                        &self.inner.id,
                        sequence,
                        &publication,
                    ))
                } else {
                    None
                }
            };
            if let Some(header) = header {
                drop(attempt);
                return Ok(Some(header));
            }

            let acknowledgement = self.inner.acknowledgement.notified();
            tokio::select! {
                _ = self.inner.cancellation.cancelled() => return Ok(None),
                changed = receiver.changed() => {
                    if changed.is_err() {
                        return Ok(None);
                    }
                }
                _ = acknowledgement => {}
            }
        }
    }

    /// Opens a scope only for a publication actually delivered by this feed and still pending ACK.
    pub fn open_scope(
        &self,
        owner_epoch: &str,
        feed_id: &str,
        delivery_sequence: u64,
    ) -> Result<StatisticsReadScope, StatisticsError> {
        let mut state = self.inner.lock_state();
        if state.closed {
            return Err(StatisticsError::Closed);
        }
        if owner_epoch != self.inner.owner_epoch || feed_id != self.inner.id {
            return Err(StatisticsError::InvalidReference);
        }
        if state.scopes.len() >= MAX_OPEN_SCOPES {
            return Err(StatisticsError::ScopeCapacity);
        }
        let publication = state
            .pending
            .iter()
            .find(|(sequence, _)| *sequence == delivery_sequence)
            .map(|(_, publication)| Arc::clone(publication))
            .ok_or(StatisticsError::InvalidReference)?;
        let scope_id = crate::studio::new_id("statistics-scope");
        let scope = ReadScopeInner::new(scope_id.clone(), &self.inner, publication);
        state.scopes.insert(scope_id, Arc::clone(&scope));
        Ok(StatisticsReadScope { inner: scope })
    }

    /// Acknowledges exactly the next contiguous delivery. Repeated old ACKs are idempotent.
    pub fn acknowledge(&self, delivery_sequence: u64) -> Result<(), StatisticsError> {
        let mut state = self.inner.lock_state();
        if delivery_sequence <= state.acknowledged_sequence {
            return Ok(());
        }
        if state.closed {
            return Err(StatisticsError::Closed);
        }
        if delivery_sequence != state.acknowledged_sequence.saturating_add(1)
            || state
                .pending
                .front()
                .is_none_or(|(sequence, _)| *sequence != delivery_sequence)
        {
            return Err(StatisticsError::InvalidReference);
        }
        state.pending.pop_front();
        state.acknowledged_sequence = delivery_sequence;
        drop(state);
        self.inner.acknowledgement.notify_one();
        Ok(())
    }

    /// Closes admission and wakes all waits. The bridge owner retains this feed until `close`
    /// confirms every in-flight next operation and scope has ended.
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), StatisticsError> {
        self.inner.request_close();
        loop {
            let changed = self.inner.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let settled = {
                let state = self.inner.lock_state();
                self.inner
                    .active_calls
                    .load(std::sync::atomic::Ordering::Acquire)
                    == 0
                    && state.scopes.is_empty()
            };
            if settled {
                return Ok(());
            }
            changed.await;
        }
    }

    pub fn id(&self) -> &str {
        &self.inner.id
    }
}

fn header_from_publication(
    feed_id: &str,
    delivery_sequence: u64,
    publication: &StatisticsPublication,
) -> StatisticsFeedHeader {
    StatisticsFeedHeader {
        owner_epoch: publication.owner_epoch.clone(),
        feed_id: feed_id.to_owned(),
        delivery_sequence,
        publication_revision: publication.publication_revision,
        summaries_revision: publication.summaries_revision,
        history_revision: publication.history_revision,
        summary_count: publication.summaries.len() as u64,
        history_count: publication.history.len() as u64,
        statistics_pending: publication.statistics_pending,
        statistics_gap: publication.statistics_gap,
        read_failed: publication.read_failed,
    }
}

impl FeedInner {
    fn lock_state(&self) -> std::sync::MutexGuard<'_, FeedState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }

    fn begin_next(self: &Arc<Self>) -> Result<FeedAttempt, StatisticsError> {
        {
            let mut state = self.lock_state();
            if state.closed {
                return Err(StatisticsError::Closed);
            }
            if state.next_in_flight {
                return Err(StatisticsError::NextInFlight);
            }
            state.next_in_flight = true;
            self.active_calls
                .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
        }
        Ok(FeedAttempt {
            feed: Arc::clone(self),
        })
    }

    fn is_closed(&self) -> bool {
        self.lock_state().closed
    }

    fn request_close(self: &Arc<Self>) {
        let scopes = {
            let mut state = self.lock_state();
            if state.closed {
                return;
            }
            state.closed = true;
            state.scopes.values().cloned().collect::<Vec<_>>()
        };
        self.cancellation.cancel();
        self.acknowledgement.notify_one();
        for scope in scopes {
            scope.request_close();
        }
        self.changed.notify_waiters();
    }

    fn remove_scope(&self, scope_id: &str) {
        let mut state = self.lock_state();
        state.scopes.remove(scope_id);
        drop(state);
        self.changed.notify_waiters();
    }
}

struct FeedAttempt {
    feed: Arc<FeedInner>,
}

impl Drop for FeedAttempt {
    fn drop(&mut self) {
        {
            let mut state = self.feed.lock_state();
            state.next_in_flight = false;
        }
        self.feed
            .active_calls
            .fetch_sub(1, std::sync::atomic::Ordering::AcqRel);
        self.feed.changed.notify_waiters();
    }
}
