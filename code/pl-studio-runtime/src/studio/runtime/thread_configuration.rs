//! Thread Configuration subscriptions of the original observation, not product account settings.
use anyhow::Result;
use pl_protocol::studio::StudioErrorCode;
pub use pl_protocol::studio::{FeedCloseReport, StudioError};
pub use pl_protocol::thread_facets::configuration::ConfigurationFrame;
pub use pl_protocol::thread_facets::identity::{ThreadFeedIdentity, ThreadObservationMode};
use std::future::Future;
use std::sync::{Arc, Mutex};

use super::StudioRuntime;
use super::thread_observation::ThreadFacetLease;
pub use super::thread_observation::facets::configuration::DeliveryStep;
use super::thread_observation::facets::configuration::{
    ConfigurationDelivery, ConfigurationInputs, cancelled,
};

struct Borrow {
    _lease: ThreadFacetLease,
    _residency: super::residency::ThreadResidencyPins,
}
pub struct StudioThreadConfiguration {
    delivery: Arc<ConfigurationDelivery>,
    pin: Mutex<Option<Borrow>>,
}
impl StudioThreadConfiguration {
    pub fn identity(&self) -> ThreadFeedIdentity {
        self.delivery.identity()
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        self.delivery.claim()
    }
    /// `send` is a bounded, synchronous, non-reentrant transport post. Only its success exposes refs.
    pub fn send_next(
        &self,
        send: impl FnOnce(ConfigurationFrame) -> Result<(), StudioError>,
    ) -> Result<DeliveryStep, StudioError> {
        self.delivery.send_next(send)
    }
    pub async fn ready(&self) {
        self.delivery.ready().await;
    }
    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        self.delivery.ack(delivery_sequence)
    }
    pub fn request_close(&self) {
        self.delivery.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        let report = self.delivery.close();
        self.pin
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        report
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}
impl Drop for StudioThreadConfiguration {
    fn drop(&mut self) {
        self.delivery.close();
    }
}

impl StudioRuntime {
    /// Live borrows the original assembled producer; Cold captures one reliable checkpoint and
    /// compatible policy baseline without activating execution. ReadCalls owns the whole opening.
    pub fn open_thread_configuration(
        &self,
        thread_id: String,
        mode: ThreadObservationMode,
    ) -> impl Future<Output = Result<StudioThreadConfiguration>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let _admission = tokio::select! { biased;
                () = runtime.shutdown_latch.committed() => return Err(cancelled().into()),
                guard = runtime.lifecycle_lock.lock() => guard,
            };
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let residency = runtime.residency.pin_many([thread_id.clone()]);
            let thread = runtime.read_protocol_thread(&thread_id).await?;
            let mode = runtime.thread_observation_mode(&thread, mode).await?;
            let lease = match mode {
                ThreadObservationMode::Live => {
                    runtime.ensure_thread_owner(&thread_id).await?;
                    runtime
                        .thread_observations
                        .live_facet_lease(&thread_id)?
                        .ok_or_else(|| {
                            StudioError::new(
                                StudioErrorCode::Unavailable,
                                "Thread Configuration observation is not installed",
                                true,
                            )
                        })?
                }
                ThreadObservationMode::Cold => {
                    let (lease, _) = runtime.thread_observations.cold_facet_sources(&thread_id)?;
                    lease
                        .source()
                        .cold_configuration
                        .get_or_try_init(|| async {
                            let checkpoint = lease
                                .source()
                                .cold_checkpoint
                                .get_or_try_init(|| async {
                                    crate::studio::thread_factory::recovery::load_checkpoint_read_only(
                                        &runtime.store,
                                        &thread,
                                    )
                                    .await?
                                    .ok_or_else(|| {
                                        anyhow::Error::new(StudioError::not_found(
                                            "Thread checkpoint",
                                        ))
                                    })
                                })
                                .await?;
                            let (inputs, config) = ConfigurationInputs::observe(
                                &runtime.config_runtime,
                                &runtime.thread_modes,
                            )?;
                            let mut value = crate::studio::thread_projection::project_runtime(
                                &thread_id,
                                &checkpoint.state,
                                thread.updated_at,
                                &checkpoint.state.usage_summary,
                            )?;
                            crate::studio::model_route::annotate_availability(
                                &mut value,
                                &thread,
                                &config.config,
                            )?;
                            lease.source().configuration.observe(
                                &value,
                                inputs.stamp,
                                inputs.mode_revision(),
                                checkpoint
                                    .state
                                    .extensions
                                    .get("studio.mode")
                                    .map(|record| record.revision),
                            )?;
                            Ok::<_, anyhow::Error>(())
                        })
                        .await?;
                    lease
                }
            };
            let projection = &lease.source().configuration;
            let delivery = projection.subscribe(lease.mode())?;
            projection.ready().await?;
            Ok(StudioThreadConfiguration {
                delivery,
                pin: Mutex::new(Some(Borrow {
                    _lease: lease,
                    _residency: residency,
                })),
            })
        })
    }
}
