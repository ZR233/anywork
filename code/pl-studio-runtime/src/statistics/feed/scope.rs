use std::sync::{Arc, Mutex, Weak};

use serde::Serialize;
use tokio::sync::Notify;

use super::{
    FeedInner, MAX_PAGE_ITEMS, MAX_SOURCE_PAGE_BYTES, StatisticsEffortPage, StatisticsError,
    StatisticsHistoryPage, StatisticsPublication, StatisticsSummary, StatisticsSummaryPage,
};

struct ScopeState {
    closed: bool,
    page_in_flight: bool,
}

pub(super) struct ReadScopeInner {
    id: String,
    feed: Weak<FeedInner>,
    publication: Arc<StatisticsPublication>,
    state: Mutex<ScopeState>,
    changed: Notify,
}

/// A source-bound immutable read scope. It owns one exact publication, not a revision-only lookup.
#[derive(Clone)]
pub struct StatisticsReadScope {
    pub(super) inner: Arc<ReadScopeInner>,
}

impl StatisticsReadScope {
    pub fn owner_epoch(&self) -> String {
        self.inner.publication.owner_epoch.clone()
    }

    pub fn feed_id(&self) -> Result<String, StatisticsError> {
        self.inner.feed_id()
    }

    pub fn scope_id(&self) -> &str {
        &self.inner.id
    }

    pub fn publication_revision(&self) -> u64 {
        self.inner.publication.publication_revision
    }

    pub fn read_summaries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<StatisticsSummaryPage, StatisticsError> {
        let _page = self.inner.begin_page()?;
        validate_page_limit(limit)?;
        let total = self.inner.publication.summaries.len();
        let (start, end) = page_bounds(offset, limit, total)?;
        let items = self.inner.publication.summaries[start..end]
            .iter()
            .map(|summary| StatisticsSummary {
                account_id: summary.account_id.clone(),
                account_display_name: summary.account_display_name.clone(),
                model_id: summary.model_id.clone(),
                sample_count: summary.sample_count,
                completion_tokens: summary.completion_tokens,
                total_ttft_millis: summary.total_ttft_millis,
                ttft_sample_count: summary.ttft_sample_count,
                total_response_millis: summary.total_response_millis,
                tokens_per_second: summary.tokens_per_second,
                average_ttft_millis: summary.average_ttft_millis,
                average_response_millis: summary.average_response_millis,
                effort_count: summary.effort_breakdowns.len() as u64,
            })
            .collect::<Vec<_>>();
        let source_bytes = source_bytes(&items)?;
        self.inner.ensure_open()?;
        Ok(StatisticsSummaryPage {
            owner_epoch: self.inner.publication.owner_epoch.clone(),
            feed_id: self.inner.feed_id()?,
            scope_id: self.inner.id.clone(),
            publication_revision: self.inner.publication.publication_revision,
            material_revision: self.inner.publication.summaries_revision,
            offset,
            total_count: total as u64,
            next_offset: page_next_offset(end, total),
            source_bytes: source_bytes as u64,
            items,
        })
    }

    pub fn read_history(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<StatisticsHistoryPage, StatisticsError> {
        let _page = self.inner.begin_page()?;
        validate_page_limit(limit)?;
        let total = self.inner.publication.history.len();
        let (start, end) = page_bounds(offset, limit, total)?;
        let items = self.inner.publication.history[start..end].to_vec();
        let source_bytes = source_bytes(&items)?;
        self.inner.ensure_open()?;
        Ok(StatisticsHistoryPage {
            owner_epoch: self.inner.publication.owner_epoch.clone(),
            feed_id: self.inner.feed_id()?,
            scope_id: self.inner.id.clone(),
            publication_revision: self.inner.publication.publication_revision,
            material_revision: self.inner.publication.history_revision,
            offset,
            total_count: total as u64,
            next_offset: page_next_offset(end, total),
            source_bytes: source_bytes as u64,
            items,
        })
    }

    pub fn read_efforts(
        &self,
        summary_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<StatisticsEffortPage, StatisticsError> {
        let _page = self.inner.begin_page()?;
        validate_page_limit(limit)?;
        let summary = self
            .inner
            .publication
            .summaries
            .get(usize::try_from(summary_index).map_err(|_| StatisticsError::InvalidReference)?)
            .ok_or(StatisticsError::InvalidReference)?;
        let total = summary.effort_breakdowns.len();
        let (start, end) = page_bounds(offset, limit, total)?;
        let items = summary.effort_breakdowns[start..end].to_vec();
        let source_bytes = source_bytes(&items)?;
        self.inner.ensure_open()?;
        Ok(StatisticsEffortPage {
            owner_epoch: self.inner.publication.owner_epoch.clone(),
            feed_id: self.inner.feed_id()?,
            scope_id: self.inner.id.clone(),
            publication_revision: self.inner.publication.publication_revision,
            material_revision: self.inner.publication.summaries_revision,
            summary_index,
            offset,
            total_count: total as u64,
            next_offset: page_next_offset(end, total),
            source_bytes: source_bytes as u64,
            items,
        })
    }

    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), StatisticsError> {
        self.inner.request_close();
        loop {
            let changed = self.inner.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let page_in_flight = self
                .inner
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .page_in_flight;
            if !page_in_flight {
                return Ok(());
            }
            changed.await;
        }
    }
}

impl ReadScopeInner {
    pub(super) fn new(
        id: String,
        feed: &Arc<FeedInner>,
        publication: Arc<StatisticsPublication>,
    ) -> Arc<Self> {
        Arc::new(Self {
            id,
            feed: Arc::downgrade(feed),
            publication,
            state: Mutex::new(ScopeState {
                closed: false,
                page_in_flight: false,
            }),
            changed: Notify::new(),
        })
    }

    fn begin_page(self: &Arc<Self>) -> Result<ScopePage, StatisticsError> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.closed || self.feed.upgrade().is_none_or(|feed| feed.is_closed()) {
            return Err(StatisticsError::Closed);
        }
        if state.page_in_flight {
            return Err(StatisticsError::PageInFlight);
        }
        state.page_in_flight = true;
        Ok(ScopePage {
            scope: Arc::clone(self),
        })
    }

    fn ensure_open(&self) -> Result<(), StatisticsError> {
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.closed || self.feed.upgrade().is_none_or(|feed| feed.is_closed()) {
            Err(StatisticsError::Closed)
        } else {
            Ok(())
        }
    }

    fn feed_id(&self) -> Result<String, StatisticsError> {
        self.feed
            .upgrade()
            .map(|feed| feed.id.clone())
            .ok_or(StatisticsError::Closed)
    }

    pub(super) fn request_close(self: &Arc<Self>) {
        let page_in_flight = {
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state.closed = true;
            state.page_in_flight
        };
        if !page_in_flight && let Some(feed) = self.feed.upgrade() {
            feed.remove_scope(&self.id);
        }
        self.changed.notify_waiters();
    }
}

struct ScopePage {
    scope: Arc<ReadScopeInner>,
}

impl Drop for ScopePage {
    fn drop(&mut self) {
        let closed = {
            let mut state = self
                .scope
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            state.page_in_flight = false;
            state.closed
        };
        self.scope.changed.notify_waiters();
        if closed && let Some(feed) = self.scope.feed.upgrade() {
            feed.remove_scope(&self.scope.id);
        }
    }
}

fn validate_page_limit(limit: u32) -> Result<(), StatisticsError> {
    if limit == 0 || limit > MAX_PAGE_ITEMS {
        Err(StatisticsError::InvalidPageLimit)
    } else {
        Ok(())
    }
}

fn page_bounds(offset: u64, limit: u32, total: usize) -> Result<(usize, usize), StatisticsError> {
    let start = usize::try_from(offset).map_err(|_| StatisticsError::InvalidReference)?;
    if start > total {
        return Err(StatisticsError::InvalidReference);
    }
    Ok((start, start.saturating_add(limit as usize).min(total)))
}

fn page_next_offset(end: usize, total: usize) -> Option<u64> {
    (end < total).then_some(end as u64)
}

fn source_bytes<T: Serialize>(items: &[T]) -> Result<usize, StatisticsError> {
    let bytes = serde_json::to_vec(items).map_err(|_| StatisticsError::PageCapacity)?;
    if bytes.len() > MAX_SOURCE_PAGE_BYTES {
        Err(StatisticsError::PageCapacity)
    } else {
        Ok(bytes.len())
    }
}
