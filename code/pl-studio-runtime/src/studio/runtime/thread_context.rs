//! Thread Context subscriptions of the original observation, not product account settings.
use anyhow::Result;
use pl_protocol::studio::StudioErrorCode;
pub use pl_protocol::studio::{FeedCloseReport, StudioError};
pub use pl_protocol::thread_facets::context::ContextFrame;
pub use pl_protocol::thread_facets::identity::{ThreadFeedIdentity, ThreadObservationMode};
use std::future::Future;
use std::sync::{Arc, Mutex};

use super::StudioRuntime;
use super::thread_observation::ThreadFacetLease;
use super::thread_observation::facets::configuration::ConfigurationInputs;
pub use super::thread_observation::facets::context::DeliveryStep;
use super::thread_observation::facets::context::{ContextDelivery, cancelled, current_policy};

struct Borrow {
    _lease: ThreadFacetLease,
    _residency: super::residency::ThreadResidencyPins,
}
pub struct StudioThreadContext {
    delivery: Arc<ContextDelivery>,
    pin: Mutex<Option<Borrow>>,
}
impl StudioThreadContext {
    pub fn identity(&self) -> ThreadFeedIdentity {
        self.delivery.identity()
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        self.delivery.claim()
    }
    /// `send` is a bounded, synchronous, non-reentrant transport post. Only its success exposes refs.
    pub fn send_next(
        &self,
        send: impl FnOnce(ContextFrame) -> Result<(), StudioError>,
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
impl Drop for StudioThreadContext {
    fn drop(&mut self) {
        self.delivery.close();
    }
}

impl StudioRuntime {
    /// Live borrows the original assembled producer; Cold captures one reliable checkpoint and
    /// compatible policy baseline without activating execution. ReadCalls owns the whole opening.
    pub fn open_thread_context(
        &self,
        thread_id: String,
        mode: ThreadObservationMode,
    ) -> impl Future<Output = Result<StudioThreadContext>> + Send + 'static + use<> {
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
            let mode = if thread.parent_thread_id.is_some()
                && (thread.role == "planner"
                    || (runtime.threads.observed_thread(&thread_id).is_none()
                        && crate::studio::agent_close::is_explicitly_closed(
                            &runtime.read_thread_state(&thread_id).await?,
                        )?))
            {
                ThreadObservationMode::Cold
            } else {
                mode
            };
            let lease = match mode {
                ThreadObservationMode::Live => {
                    runtime.ensure_thread_owner(&thread_id).await?;
                    runtime
                        .thread_observations
                        .live_facet_lease(&thread_id)?
                        .ok_or_else(|| {
                            StudioError::new(
                                StudioErrorCode::Unavailable,
                                "Thread Context observation is not installed",
                                true,
                            )
                        })?
                }
                ThreadObservationMode::Cold => {
                    let (lease, _) = runtime.thread_observations.cold_facet_sources(&thread_id)?;
                    lease
                        .source()
                        .cold_context
                        .get_or_try_init(|| async {
                            let checkpoint = lease
                                .source()
                                .cold_checkpoint
                                .get_or_try_init(|| async {
                                    crate::studio::thread_factory::recovery::load_checkpoint(
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
                            let policy = current_policy(
                                &config.config,
                                value.model_route.as_ref(),
                                inputs.stamp,
                                inputs.mode_revision(),
                            )?;
                            lease
                                .source()
                                .metrics
                                .observe(&checkpoint.state, &checkpoint.state.usage_summary);
                            lease.source().context.observe(
                                &value,
                                policy,
                                lease.source().metrics.snapshot()?,
                            )?;
                            Ok::<_, anyhow::Error>(())
                        })
                        .await?;
                    lease
                }
            };
            let projection = &lease.source().context;
            let delivery = projection.subscribe(lease.mode())?;
            projection.ready().await?;
            Ok(StudioThreadContext {
                delivery,
                pin: Mutex::new(Some(Borrow {
                    _lease: lease,
                    _residency: residency,
                })),
            })
        })
    }
}
