//! Facet sources attached to the original observation entry, never another Thread worker.
use super::super::observation_ids::ObservationIds;
use super::super::thread_reads::lifetime::{ThreadReadGroup, ThreadReadRegistry};
use pl_protocol::studio::StudioError;
use pl_protocol::thread_facets::identity::FeedClosedReason;
use std::sync::Arc;

pub(in crate::studio::runtime) mod authoring;
pub(in crate::studio::runtime) mod configuration;
pub(in crate::studio::runtime) mod context;
pub(in crate::studio::runtime) mod execution;
pub(in crate::studio::runtime) mod metrics;

pub(in crate::studio::runtime) struct ThreadFacetSources {
    pub(in crate::studio::runtime) metrics: Arc<metrics::MetricsProjection>,
    pub(in crate::studio::runtime) execution: Arc<execution::ExecutionProjection>,
    pub(in crate::studio::runtime) authoring: Arc<authoring::AuthoringProjection>,
    pub(in crate::studio::runtime) configuration: Arc<configuration::ConfigurationProjection>,
    pub(in crate::studio::runtime) context: Arc<context::ContextProjection>,
    pub(in crate::studio::runtime) reads: ThreadReadGroup,
    pub(in crate::studio::runtime) cold_checkpoint:
        tokio::sync::OnceCell<pl_core::thread::ThreadCheckpoint>,
    pub(in crate::studio::runtime) cold_execution: tokio::sync::OnceCell<()>,
    pub(in crate::studio::runtime) cold_authoring: tokio::sync::OnceCell<()>,
    pub(in crate::studio::runtime) cold_configuration: tokio::sync::OnceCell<()>,
    pub(in crate::studio::runtime) cold_context: tokio::sync::OnceCell<()>,
}

impl ThreadFacetSources {
    pub(super) fn new(
        ids: &ObservationIds,
        reads: &ThreadReadRegistry,
        thread_id: &str,
    ) -> Result<Arc<Self>, StudioError> {
        let incarnation = ids.next()?;
        Ok(Arc::new(Self {
            reads: reads.group(thread_id, ids.epoch(), incarnation),
            cold_checkpoint: tokio::sync::OnceCell::new(),
            cold_execution: tokio::sync::OnceCell::new(),
            cold_authoring: tokio::sync::OnceCell::new(),
            cold_configuration: tokio::sync::OnceCell::new(),
            cold_context: tokio::sync::OnceCell::new(),
            context: Arc::new(context::ContextProjection::new(
                ids.epoch().to_owned(),
                incarnation,
            )),
            configuration: Arc::new(configuration::ConfigurationProjection::new(
                ids.epoch().to_owned(),
                incarnation,
            )),
            authoring: Arc::new(authoring::AuthoringProjection::new(
                thread_id.to_owned(),
                ids.epoch().to_owned(),
                incarnation,
            )),
            execution: Arc::new(execution::ExecutionProjection::new(
                ids.epoch().to_owned(),
                incarnation,
            )),
            metrics: Arc::new(metrics::MetricsProjection::new(
                ids.epoch().to_owned(),
                incarnation,
            )),
        }))
    }

    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        self.reads.request_close();
        self.metrics.close(reason);
        self.execution.close(reason);
        self.authoring.close(reason);
        self.configuration.close(reason);
        self.context.close(reason);
    }
}
