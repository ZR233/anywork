//! A concrete metrics source registered in the original Thread observation owner.
use std::sync::Arc;

use anyhow::{Context, Result};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::identity::{
    FeedClosedReason, ThreadFacet, ThreadFacetStamp, ThreadFeedIdentity, ThreadObservationMode,
};
use pl_protocol::thread_facets::metrics::MetricsValue;
use tokio::sync::watch;

use super::StudioRuntime;
use super::thread_observation::facets::metrics::{
    MetricsProjection, MetricsPublication, MetricsSnapshot,
};

/// Holds the original immutable identity sources as well as their bounded numeric values.
#[derive(Clone)]
pub struct StudioMetricsSample {
    snapshot: Arc<MetricsSnapshot>,
    projection: Arc<MetricsProjection>,
    // Unacknowledged samples retain this feed's registered borrow after producer termination.
    _lease: Arc<super::thread_observation::ThreadFacetLease>,
}

impl StudioMetricsSample {
    pub fn stamp(&self) -> ThreadFacetStamp {
        self.snapshot.stamp.clone()
    }
    pub fn value(&self) -> MetricsValue {
        self.snapshot.value.clone()
    }

    /// The host invokes this around its actual non-awaiting Data send, not around conversion.
    pub fn deliver<T>(
        &self,
        send: impl FnOnce() -> Result<T, StudioError>,
    ) -> Result<T, StudioError> {
        self.projection.deliver(&self.snapshot, send)
    }
}

pub enum StudioMetricsSourceEvent {
    Sample(StudioMetricsSample),
    Failure(StudioError),
    Closed(FeedClosedReason),
}

pub struct StudioThreadMetricsSource {
    identity: ThreadFeedIdentity,
    initial: Option<StudioMetricsSample>,
    observed: watch::Receiver<MetricsPublication>,
    mode: ThreadObservationMode,
    _projection: Arc<MetricsProjection>,
    _lease: Arc<super::thread_observation::ThreadFacetLease>,
    _residency: super::residency::ThreadResidencyPins,
}

impl StudioThreadMetricsSource {
    pub fn identity(&self) -> ThreadFeedIdentity {
        self.identity.clone()
    }
    pub fn take_initial(&mut self) -> Result<StudioMetricsSample, StudioError> {
        self.initial.take().ok_or_else(|| {
            StudioError::new(
                StudioErrorCode::Protocol,
                "Thread metrics baseline was already taken",
                false,
            )
        })
    }
    pub fn mode(&self) -> ThreadObservationMode {
        self.mode
    }
    pub fn ensure_current(&self) -> Result<(), StudioError> {
        self._projection.ensure_open()
    }

    /// An already published source terminal. Data is not a possible terminal result.
    pub fn terminal(&self) -> Option<Result<FeedClosedReason, StudioError>> {
        if self.mode == ThreadObservationMode::Cold {
            return self._projection.current_close_reason().map(Ok);
        }
        match self._projection.terminal()? {
            MetricsPublication::Failure(error) => Some(Err(error)),
            MetricsPublication::Closed(reason) => Some(Ok(reason)),
            MetricsPublication::Pending | MetricsPublication::Ready(_) => None,
        }
    }

    pub async fn changed(&mut self) -> Result<StudioMetricsSourceEvent> {
        if let Some(terminal) = self.terminal() {
            return Ok(match terminal {
                Ok(reason) => StudioMetricsSourceEvent::Closed(reason),
                Err(error) => StudioMetricsSourceEvent::Failure(error),
            });
        }
        if self.mode == ThreadObservationMode::Cold {
            // Freeze the successful baseline; do not consume live token publications just to
            // discard them. Only the original owner's replacement/closure can end this source.
            return Ok(StudioMetricsSourceEvent::Closed(
                self._projection.closed_reason().await?,
            ));
        }
        loop {
            self.observed
                .changed()
                .await
                .context("Thread metrics source ended without a typed terminal")?;
            let event = self.observed.borrow_and_update().clone();
            match event {
                MetricsPublication::Ready(snapshot) if self.mode == ThreadObservationMode::Live => {
                    return Ok(StudioMetricsSourceEvent::Sample(StudioMetricsSample {
                        snapshot,
                        projection: self._projection.clone(),
                        _lease: self._lease.clone(),
                    }));
                }
                MetricsPublication::Failure(error) => {
                    return Ok(StudioMetricsSourceEvent::Failure(error));
                }
                MetricsPublication::Closed(reason) => {
                    return Ok(StudioMetricsSourceEvent::Closed(reason));
                }
                MetricsPublication::Pending | MetricsPublication::Ready(_) => {}
            }
        }
    }
}

impl StudioRuntime {
    /// Register the entire opening before returning its Future; dropping a caller never abandons
    /// an accepted checkpoint read/activation. Cold requests never ensure an execution owner.
    pub fn open_thread_metrics(
        &self,
        thread_id: String,
        mode: ThreadObservationMode,
    ) -> impl std::future::Future<Output = Result<StudioThreadMetricsSource>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        let feed_id = crate::studio::new_id("thread-feed");
        self.read_calls.run(async move {
            // A queued opening owns no IO yet. The existing shutdown latch prevents a
            // lifecycle -> read-call join -> lifecycle cycle without aborting admitted IO.
            let _admission = tokio::select! { biased;
                () = runtime.shutdown_latch.committed() => return Err(closed().into()),
                guard = runtime.lifecycle_lock.lock() => guard,
            };
            if runtime.shutdown_committed() {
                return Err(closed().into());
            }
            let residency = runtime.residency.pin_many([thread_id.clone()]);
            let thread = runtime.read_protocol_thread(&thread_id).await?;
            let mode = if thread.parent_thread_id.is_some() && thread.role == "planner" {
                ThreadObservationMode::Cold
            } else {
                mode
            };
            let lease = if mode == ThreadObservationMode::Live {
                runtime.ensure_thread_owner(&thread_id).await?;
                runtime
                    .thread_observations
                    .live_facet_lease(&thread_id)?
                    .ok_or_else(|| {
                        StudioError::new(
                            StudioErrorCode::Unavailable,
                            "Thread metrics observation was not installed",
                            true,
                        )
                    })?
            } else {
                let (lease, opening) =
                    runtime.thread_observations.cold_facet_sources(&thread_id)?;
                if opening || lease.source().metrics.needs_seed() {
                    let result = lease
                        .source()
                        .cold_checkpoint
                        .get_or_try_init(|| async {
                            crate::studio::thread_factory::recovery::load_checkpoint(
                                &runtime.store,
                                &thread,
                            )
                            .await?
                            .ok_or_else(|| {
                                anyhow::Error::new(StudioError::not_found("Thread checkpoint"))
                            })
                        })
                        .await;
                    lease.source().metrics.ensure_open()?;
                    match result {
                        Ok(checkpoint) => {
                            let usage = runtime
                                .store
                                .thread_persistence()
                                .usage(&thread_id)
                                .unwrap_or_else(|| checkpoint.state.usage_summary.clone());
                            lease.source().metrics.observe(&checkpoint.state, &usage);
                        }
                        Err(error) => {
                            lease
                                .source()
                                .metrics
                                .fail(crate::studio_error_from_anyhow_ref(&error));
                            runtime.thread_observations.discard_cold_sources(&lease);
                            return Err(error);
                        }
                    }
                }
                lease
            };
            let lease = Arc::new(lease);
            let source = lease.source().metrics.clone();
            let mut observed = source.subscribe();
            let initial = loop {
                source.ensure_open()?;
                let state = observed.borrow_and_update().clone();
                match state {
                    MetricsPublication::Ready(snapshot) => {
                        break StudioMetricsSample {
                            snapshot,
                            projection: source.clone(),
                            _lease: lease.clone(),
                        };
                    }
                    MetricsPublication::Failure(error) => return Err(error.into()),
                    MetricsPublication::Closed(_) => return Err(closed().into()),
                    MetricsPublication::Pending => observed
                        .changed()
                        .await
                        .context("Thread metrics source ended during opening")?,
                }
            };
            source.ensure_open()?;
            let stamp = initial.stamp();
            let identity = ThreadFeedIdentity {
                feed_id,
                runtime_epoch: stamp.runtime_epoch,
                incarnation: stamp.incarnation,
                facet: ThreadFacet::Metrics,
                mode,
            };
            Ok(StudioThreadMetricsSource {
                identity,
                initial: Some(initial),
                observed,
                mode,
                _projection: source,
                _lease: lease,
                _residency: residency,
            })
        })
    }
}

fn closed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Thread metrics opening was cancelled",
        false,
    )
}
