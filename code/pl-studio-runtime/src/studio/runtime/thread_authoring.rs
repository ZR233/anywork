//! Authoring subscriptions of the original Thread facet source. No execution or second producer.
use anyhow::Result;
use pl_protocol::studio::StudioErrorCode;
pub use pl_protocol::studio::{FeedCloseReport, StudioError};
pub use pl_protocol::thread_facets::authoring::AuthoringFrame;
pub use pl_protocol::thread_facets::identity::{ThreadFeedIdentity, ThreadObservationMode};
use std::future::Future;
use std::sync::{Arc, Mutex};

use super::StudioRuntime;
use super::thread_observation::ThreadFacetLease;
pub use super::thread_observation::facets::authoring::DeliveryStep;
use super::thread_observation::facets::authoring::{AuthoringDelivery, cancelled};

struct Borrow {
    _lease: ThreadFacetLease,
    _residency: super::residency::ThreadResidencyPins,
}
pub struct StudioThreadAuthoring {
    delivery: Arc<AuthoringDelivery>,
    pin: Mutex<Option<Borrow>>,
}
impl StudioThreadAuthoring {
    pub fn identity(&self) -> ThreadFeedIdentity {
        self.delivery.identity()
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        self.delivery.claim()
    }
    /// `send` must be bounded and non-reentrant (FRB port post / HTTP body poll), never blocking
    /// IO or a call back into this projection. Only its actual success exposes immutable refs.
    pub fn send_next(
        &self,
        send: impl FnOnce(AuthoringFrame) -> Result<(), StudioError>,
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
impl Drop for StudioThreadAuthoring {
    fn drop(&mut self) {
        self.delivery.close();
    }
}

impl StudioRuntime {
    /// Live joins the original assembled observation; Cold only pins a reliable checkpoint.
    /// ReadCalls owns opening through actual completion, even when the caller loses its reply.
    pub fn open_thread_authoring(
        &self,
        thread_id: String,
        mode: ThreadObservationMode,
    ) -> impl Future<Output = Result<StudioThreadAuthoring>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            // A queued opening owns no IO yet. The existing shutdown latch prevents a
            // lifecycle -> read-call join -> lifecycle cycle without aborting admitted IO.
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
                                "Authoring observation is not installed",
                                true,
                            )
                        })?
                }
                ThreadObservationMode::Cold => {
                    let (lease, _) = runtime.thread_observations.cold_facet_sources(&thread_id)?;
                    lease
                        .source()
                        .cold_authoring
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
                            lease.source().authoring.seed(&checkpoint.state);
                            lease.source().authoring.ready().await?;
                            Ok::<_, anyhow::Error>(())
                        })
                        .await?;
                    lease
                }
            };
            let projection = &lease.source().authoring;
            let delivery = projection.subscribe(lease.mode())?;
            projection.ready().await?;
            Ok(StudioThreadAuthoring {
                delivery,
                pin: Mutex::new(Some(Borrow {
                    _lease: lease,
                    _residency: residency,
                })),
            })
        })
    }
}
