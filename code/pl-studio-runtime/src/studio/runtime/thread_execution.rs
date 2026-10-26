//! Concrete execution subscriptions and non-activating borrows of an exact assembled owner.
use anyhow::{Context, Result};
pub use pl_core::thread::ThreadHandle;
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, StudioErrorCode, StudioShutdownIssue,
};
pub use pl_protocol::studio::{FeedCloseReport, StudioError};
pub use pl_protocol::thread_facets::execution::ExecutionFrame;
pub use pl_protocol::thread_facets::identity::{ThreadFeedIdentity, ThreadObservationMode};
use std::collections::BTreeMap;
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};
use tokio_util::sync::CancellationToken;

use super::StudioRuntime;
use super::background_task::BackgroundTask;
use super::read_calls::ReadCalls;
use super::thread_observation::ThreadFacetLease;
pub use super::thread_observation::facets::execution::DeliveryStep;
use super::thread_observation::facets::execution::{
    ExecutionDelivery, ExecutionProjection, cancelled,
};

struct Borrow {
    _lease: Arc<ThreadFacetLease>,
    _residency: Arc<super::residency::ThreadResidencyPins>,
}

pub struct StudioThreadExecution {
    delivery: Arc<ExecutionDelivery>,
    pin: Arc<Mutex<Option<Arc<Borrow>>>>,
    _handoff: Option<PendingHandoff>,
}

impl StudioThreadExecution {
    pub fn identity(&self) -> ThreadFeedIdentity {
        self.delivery.identity()
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        self.delivery.claim()
    }
    /// Synchronously posts at most one frame under the native publication guard. `send` must be
    /// bounded and non-reentrant (FRB port post / HTTP body poll), and must not perform blocking IO
    /// or call back into this projection. A failed post never exposes refs or advances sent.
    pub fn send_next(
        &self,
        send: impl FnOnce(ExecutionFrame) -> Result<(), StudioError>,
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

impl Drop for StudioThreadExecution {
    fn drop(&mut self) {
        self.delivery.close();
    }
}

struct PinState {
    closing: bool,
    borrow: Option<Arc<Borrow>>,
    opens: BTreeMap<String, Arc<BackgroundTask>>,
    pending: BTreeMap<String, PendingExecution>,
    issues: BTreeMap<String, FeedCloseIssue>,
}

// A successful open remains closeable by its source until the caller actually takes it. Merely
// joining the worker must not strand an independent feed pin inside an unpolled oneshot result.
struct PendingExecution {
    delivery: Arc<ExecutionDelivery>,
    pin: Arc<Mutex<Option<Arc<Borrow>>>>,
}
struct PendingHandoff {
    state: Weak<Mutex<PinState>>,
    id: String,
}
impl Drop for PendingHandoff {
    fn drop(&mut self) {
        if let Some(state) = self.state.upgrade() {
            state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .pending
                .remove(&self.id);
        }
    }
}

/// Captured from a concrete ThreadHandle's original observation. It never follows a current ID,
/// ensures another execution owner or reinterprets a cold/metrics feed as the created source.
pub struct StudioExecutionSourcePin {
    id: String,
    thread_id: String,
    epoch: String,
    incarnation: u64,
    projection: Arc<ExecutionProjection>,
    calls: ReadCalls,
    cancel: CancellationToken,
    state: Arc<Mutex<PinState>>,
}

impl StudioExecutionSourcePin {
    pub fn thread_id(&self) -> String {
        self.thread_id.clone()
    }
    pub fn runtime_epoch(&self) -> String {
        self.epoch.clone()
    }
    pub fn incarnation(&self) -> u64 {
        self.incarnation
    }

    /// Opening is registered before returning. Caller cancellation cannot abandon its native
    /// task; a late/lost result owns its own independent borrow and closes when discarded.
    pub fn open_execution(
        &self,
    ) -> impl Future<Output = Result<StudioThreadExecution>> + Send + 'static + use<> {
        let open_id = crate::studio::new_id("execution-open");
        let admitted = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing {
                Err(anyhow::Error::new(cancelled()))
            } else {
                state.opens.retain(|_, task| !task.succeeded());
                match state.borrow.clone() {
                    None => Err(cancelled().into()),
                    Some(pin) => {
                        let projection = self.projection.clone();
                        let cancel = self.cancel.clone();
                        let handoff = self.state.clone();
                        let id = open_id.clone();
                        self.calls
                            .register(async move {
                                if cancel.is_cancelled() {
                                    return Err(cancelled().into());
                                }
                                let delivery = projection.subscribe(pin._lease.mode())?;
                                tokio::select! { biased;
                                    () = cancel.cancelled() => return Err(cancelled().into()),
                                    ready = projection.ready() => ready?,
                                }
                                if cancel.is_cancelled() {
                                    return Err(cancelled().into());
                                }
                                let pin = Arc::new(Mutex::new(Some(pin)));
                                let feed = StudioThreadExecution {
                                    delivery: delivery.clone(),
                                    pin: pin.clone(),
                                    _handoff: Some(PendingHandoff {
                                        state: Arc::downgrade(&handoff),
                                        id: id.clone(),
                                    }),
                                };
                                let closing = {
                                    let mut state = handoff
                                        .lock()
                                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                                    if state.closing {
                                        true
                                    } else {
                                        state
                                            .pending
                                            .insert(id, PendingExecution { delivery, pin });
                                        false
                                    }
                                };
                                if closing {
                                    return Err(cancelled().into());
                                }
                                Ok(feed)
                            })
                            .inspect(|call| {
                                state.opens.insert(call.id.clone(), call.task.clone());
                            })
                    }
                }
            }
        };
        let handoff = self.state.clone();
        async move {
            let result = admitted?.wait().await;
            // Handoff and requestClose use the same guard, not a later cancellation-token write.
            // If close won this boundary, this late result is never exposed as a new feed.
            let closing = {
                let mut state = handoff
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if state.closing {
                    true
                } else {
                    state.pending.remove(&open_id);
                    false
                }
            };
            if closing {
                if let Ok(feed) = result {
                    let _ = feed.close().await;
                }
                return Err(cancelled().into());
            }
            result
        }
    }

    pub fn request_close(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing = true;
        self.cancel.cancel();
    }

    pub async fn close(&self) -> FeedCloseReport {
        self.request_close();
        let tasks: Vec<_> = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .opens
            .iter()
            .map(|(id, task)| (id.clone(), task.clone()))
            .collect();
        let results = futures::future::join_all(tasks.iter().map(|(_, task)| task.join())).await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for ((id, _), result) in tasks.iter().zip(results) {
            if result.is_err() {
                state
                    .issues
                    .entry(id.clone())
                    .or_insert_with(|| FeedCloseIssue {
                        diagnostic: StudioShutdownIssue {
                            stage: "executionSource".into(),
                            code: "openJoinError".into(),
                            message:
                                "An original execution-source opening did not join successfully"
                                    .into(),
                            retryable: false,
                            correlation_id: StudioError::internal().correlation_id,
                        },
                        recovery: CleanupRecovery::Terminal,
                    });
            }
        }
        let pending = std::mem::take(&mut state.pending);
        // No accepted worker can add another pending result after the joins and closing fence.
        // Already handed-off feeds are absent here and retain their independent source borrow.
        for (_, pending) in pending {
            pending.delivery.close();
            pending
                .pin
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
        }
        if state.issues.is_empty() {
            state.borrow.take();
        }
        let issues = state.issues.values().cloned().collect::<Vec<_>>();
        FeedCloseReport {
            feed_id: self.id.clone(),
            outcome: if issues.is_empty() {
                FeedCloseOutcome::Clean
            } else {
                FeedCloseOutcome::Unresolved { issues }
            },
        }
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl Drop for StudioExecutionSourcePin {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl StudioRuntime {
    pub fn capture_execution_source(
        &self,
        original_thread: &ThreadHandle,
    ) -> Result<StudioExecutionSourcePin> {
        if self.shutdown_committed() {
            return Err(cancelled().into());
        }
        let lease = self
            .thread_observations
            .execution_lease_for(original_thread)?;
        let thread_id = lease.thread_id().to_owned();
        let projection = lease.source().execution.clone();
        let (epoch, incarnation) = projection.origin();
        let pin = Arc::new(Borrow {
            _lease: Arc::new(lease),
            _residency: Arc::new(self.residency.pin_many([thread_id.clone()])),
        });
        Ok(StudioExecutionSourcePin {
            id: crate::studio::new_id("execution-source"),
            thread_id,
            epoch,
            incarnation,
            projection,
            calls: self.read_calls.clone(),
            cancel: CancellationToken::new(),
            state: Arc::new(Mutex::new(PinState {
                closing: false,
                borrow: Some(pin),
                opens: BTreeMap::new(),
                pending: BTreeMap::new(),
                issues: BTreeMap::new(),
            })),
        })
    }

    pub fn open_thread_execution(
        &self,
        thread_id: String,
        mode: ThreadObservationMode,
    ) -> impl Future<Output = Result<StudioThreadExecution>> + Send + 'static + use<> {
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
            let residency = Arc::new(runtime.residency.pin_many([thread_id.clone()]));
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
                                "Execution observation is not installed",
                                true,
                            )
                        })?
                }
                ThreadObservationMode::Cold => {
                    let (lease, _) = runtime.thread_observations.cold_facet_sources(&thread_id)?;
                    lease
                        .source()
                        .cold_execution
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
                            let recent = runtime
                                .store
                                .history(&thread_id)
                                .await?
                                .newest_terminal_turn()
                                .await?;
                            if recent
                                .as_ref()
                                .is_some_and(|turn| turn.revision > checkpoint.history_fence)
                            {
                                return Err(StudioError::new(
                                    StudioErrorCode::Superseded,
                                    "Cold execution facts changed during capture",
                                    true,
                                )
                                .into());
                            }
                            let activity = crate::studio::thread_projection::project_activity(
                                &thread_id,
                                &checkpoint.state,
                                None,
                            )
                            .map(Arc::new);
                            let storage =
                                runtime
                                    .thread_persistence_snapshot(&thread_id)
                                    .map(|detail| {
                                        Arc::new(crate::studio::thread_projection::storage_state(
                                            &checkpoint.state,
                                            &detail,
                                        ))
                                    });
                            let hosted = if thread.parent_thread_id.is_none() {
                                runtime.thread_observations.cold_hosted_interactions(&thread_id).await?
                            } else {
                                Vec::new()
                            };
                            lease.source().execution.observe(
                                &thread_id,
                                thread.updated_at,
                                &checkpoint.state,
                                recent.map(Arc::new),
                                activity,
                                storage,
                                &[],
                                Some(&hosted),
                            );
                            lease.source().execution.ensure_open()?;
                            Ok::<_, anyhow::Error>(())
                        })
                        .await?;
                    lease
                }
            };
            let lease = Arc::new(lease);
            let projection = lease.source().execution.clone();
            let delivery = projection.subscribe(lease.mode())?;
            projection
                .ready()
                .await
                .context("Execution baseline was not published")?;
            let pin = Arc::new(Borrow {
                _lease: lease,
                _residency: residency,
            });
            Ok(StudioThreadExecution {
                delivery,
                pin: Arc::new(Mutex::new(Some(pin))),
                _handoff: None,
            })
        })
    }
}
