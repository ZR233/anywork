//! Facet sources attached to the original observation entry, never another Thread worker.
use std::sync::Arc;
use pl_protocol::studio::StudioError;
use pl_protocol::thread_facets::identity::FeedClosedReason;
use super::super::observation_ids::ObservationIds;
use super::super::thread_reads::lifetime::{ThreadReadGroup, ThreadReadRegistry};

pub(in crate::studio::runtime) mod metrics;

pub(in crate::studio::runtime) struct ThreadFacetSources {
    pub(in crate::studio::runtime) metrics: Arc<metrics::MetricsProjection>,
    pub(in crate::studio::runtime) reads: ThreadReadGroup,
}

impl ThreadFacetSources {
    pub(super) fn new(ids: &ObservationIds,
        reads: &ThreadReadRegistry, thread_id: &str) -> Result<Arc<Self>, StudioError> {
        let incarnation = ids.next()?;
        Ok(Arc::new(Self { reads: reads.group(thread_id, ids.epoch(), incarnation),
            metrics: Arc::new(metrics::MetricsProjection::new(
            ids.epoch().to_owned(), incarnation,
        )) }))
    }

    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        self.reads.request_close();
        self.metrics.close(reason);
}
}
