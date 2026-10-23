//! Concrete metrics delivery: one original runtime source, a two-Data ACK window and latest one.
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::identity::{FeedClosedReason, ThreadFeedIdentity, ThreadObservationMode};
use pl_protocol::thread_facets::metrics::{MetricsEvent, MetricsFrame};
use pl_studio_runtime::{StudioMetricsSample, StudioMetricsSourceEvent, StudioThreadMetricsSource};
use tokio::sync::{Notify, oneshot};

use crate::api::studio::bridge_runtime::current_bridge;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;
use super::identity::BridgeThreadObservationMode;
use super::metrics::BridgeMetricsFrame;

const DATA_BYTES: usize = 64 * 1024;

struct Window {
    sink: Option<StreamSink<BridgeMetricsFrame>>,
    claimed: bool,
    control_sent: bool,
    sent: u64,
    acked: u64,
    unacked: VecDeque<(u64, StudioMetricsSample)>,
}

struct MetricsOwner {
    task: Arc<TypedFeedTask>,
    window: Mutex<Window>,
    changed: Notify,
}

/// Closing this listener never closes the core Thread, its model or its writer.
pub struct BridgeThreadMetrics {
    owner: Arc<MetricsOwner>,
    registry: &'static crate::api::studio::subscription::BridgeTaskRegistry,
    feed_id: String,
}

/// The opening and its eventual producer share one registered retained completion. There is no
/// orphan async open, detached sink, Dart next pump or second aggregation of runtime snapshots.
pub async fn open_thread_metrics(thread_id: String, mode: BridgeThreadObservationMode) -> Result<BridgeThreadMetrics, BridgeError> {
    let bridge = current_bridge().ok_or_else(|| BridgeError::from(StudioError::new(
        StudioErrorCode::NotInitialized, "Studio runtime is not initialized", false)))?;
    let task = TypedFeedTask::new(bridge.subscriptions.next_id(), bridge.shutdown.child_token());
    let owner = Arc::new(MetricsOwner { task: task.clone(), window: Mutex::new(Window {
        sink: None, claimed: false, control_sent: false, sent: 0, acked: 0,
        unacked: VecDeque::with_capacity(2),
    }), changed: Notify::new() });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    task.start(async move {
        let mode = match mode { BridgeThreadObservationMode::Live => ThreadObservationMode::Live,
            BridgeThreadObservationMode::Cold => ThreadObservationMode::Cold };
        // Never drop this future to cancel activation/storage IO. Its runtime call owner and this
        // producer both join the actual opening; cancellation only prevents the late handoff.
        let mut source = match bridge.studio.open_thread_metrics(thread_id, mode).await {
            Ok(source) => source,
            Err(error) => {
                // No handle or Data was handed off. Mark this rejected opening closed so its
                // real completion can be pruned without confusing a natural feed terminal.
                producer.task.signal_cancel();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        let identity = source.identity();
        let installed = producer.task.admit(|| {
            source.ensure_current().map_err(BridgeError::from)?;
            Ok(identity.feed_id.clone())
        });
        match installed {
            Ok(feed_id) => {
                if opened.send(Ok(feed_id)).is_err() { producer.task.signal_cancel(); return; }
            }
            Err(error) => {
                producer.task.signal_cancel();
                let _ = opened.send(Err(error));
                return;
            }
        }
        if !producer.wait_sink().await { return; }
        let result = std::panic::AssertUnwindSafe(run_delivery(&producer, &mut source, identity.clone()))
            .catch_unwind().await;
        if let Err(panic) = result {
            if let Err(error) = producer.send_control(MetricsFrame::Failure { identity, error: StudioError::internal() }) {
                producer.task.record_failure(error);
            }
            // A best-effort typed terminal does not turn the actual failed task into Clean.
            std::panic::resume_unwind(panic);
        }
    })?;
    let feed_id = match ready.await {
        Ok(result) => result?,
        Err(_) => {
            // A panic before publishing the open result is still recorded in the registered task.
            owner.task.signal_cancel();
            return Err(StudioError::internal().into());
        }
    };
    Ok(BridgeThreadMetrics { owner, registry: &bridge.subscriptions, feed_id })
}

impl BridgeThreadMetrics {
    pub async fn stream(&self, sink: StreamSink<BridgeMetricsFrame>) -> Result<(), BridgeError> {
        self.owner.task.admit(|| {
            let mut window = self.owner.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if window.claimed {
                return Err(StudioError::new(StudioErrorCode::Conflict, "Thread metrics stream was already claimed", false).into());
            }
            window.claimed = true;
            window.sink = Some(sink);
            Ok(())
        })?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        self.owner.task.admit(|| {
            let mut window = self.owner.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if delivery_sequence == 0 || delivery_sequence <= window.acked { return Ok(()); }
            if delivery_sequence > window.sent {
                return Err(StudioError::new(StudioErrorCode::Protocol, "Metrics ACK exceeds the sent prefix", false).into());
            }
            window.acked = delivery_sequence;
            while window.unacked.front().is_some_and(|(sequence, _)| *sequence <= delivery_sequence) {
                window.unacked.pop_front();
            }
            Ok(())
        })?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) { self.owner.task.signal_cancel(); }

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let stopped = self.owner.task.wait_stopped().await;
        let outcome = if stopped.is_ok() {
            let mut window = self.owner.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            window.sink = None;
            window.unacked.clear();
            drop(window);
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues: self.owner.task.close_issues() }
        };
        Ok(BridgeFeedCloseReport { feed_id: self.feed_id.clone(), outcome })
    }

    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> { self.close().await }
}

impl Drop for BridgeThreadMetrics {
    fn drop(&mut self) { self.request_close(); }
}

impl MetricsOwner {
    async fn wait_sink(&self) -> bool {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.task.cancel().is_cancelled() { return false; }
            if self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner).claimed { return true; }
            tokio::select! { biased;
                () = self.task.cancel().cancelled() => return false,
                () = changed => {}
            }
        }
    }

    fn send_data(&self, identity: &ThreadFeedIdentity, sample: &StudioMetricsSample, baseline: bool) -> Result<bool, StudioError> {
        self.task.admit_studio(|| {
            let mut window = self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if window.unacked.len() == 2 { return Ok(false); }
            let sequence = window.sent.checked_add(1).ok_or_else(|| StudioError::new(
                StudioErrorCode::Overloaded, "Metrics delivery sequence is exhausted", false))?;
            let event = if baseline {
                MetricsEvent::Baseline { identity: identity.clone(), stamp: sample.stamp(), value: sample.value() }
            } else { MetricsEvent::Replace { stamp: sample.stamp(), value: sample.value() } };
            let frame = MetricsFrame::Data { delivery_sequence: sequence, event };
            let bytes = serde_json::to_vec(&frame).map_err(|_| StudioError::new(
                StudioErrorCode::Protocol, "Metrics Data could not be serialized", false))?;
            if bytes.len() > DATA_BYTES {
                return Err(StudioError::new(StudioErrorCode::Overloaded, "Metrics Data exceeds its JSON byte budget", false));
            }
            let sink = window.sink.as_ref().ok_or_else(|| StudioError::new(
                StudioErrorCode::Cancelled, "Thread metrics delivery is closed", false))?;
            // StreamSink.add posts to the FRB port without waiting for Dart or reentering this owner.
            sample.deliver(|| sink.add(frame.into()).map_err(|_|
                StudioError::new(StudioErrorCode::Unavailable, "Thread metrics stream sink is unavailable", false)))?;
            window.sent = sequence;
            window.unacked.push_back((sequence, sample.clone()));
            Ok(true)
        })
    }

    fn send_control(&self, frame: MetricsFrame) -> Result<(), BridgeError> {
        let mut window = self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.control_sent { return Ok(()); }
        window.control_sent = true;
        if let Some(sink) = &window.sink { sink.add(frame.into()).map_err(|_| transport_failed())?; }
        Ok(())
    }
}

impl TypedFeedResource for MetricsOwner {
    fn release_after_join(&self) {
        let mut window = self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        window.sink = None;
        window.unacked.clear();
    }
}

async fn run_delivery(owner: &MetricsOwner, source: &mut StudioThreadMetricsSource, identity: ThreadFeedIdentity) {
    let initial = match source.take_initial() {
        Ok(initial) => initial,
        Err(error) => { owner.task.record_failure(error.clone().into());
            if let Err(error) = owner.send_control(MetricsFrame::Failure { identity, error }) { owner.task.record_failure(error); }
            return; }
    };
    let mut pending = Some(initial);
    let mut baseline = true;
    loop {
        let changed = owner.changed.notified();
        tokio::pin!(changed);
        changed.as_mut().enable();
        if let Some(terminal) = source.terminal() {
            let frame = match terminal {
                Err(error) => MetricsFrame::Failure { identity, error },
                Ok(reason) => MetricsFrame::Closed { identity, reason },
            };
            if let Err(error) = owner.send_control(frame) { owner.task.record_failure(error); }
            return;
        }
        if let Some(sample) = &pending {
            match owner.send_data(&identity, sample, baseline) {
                Ok(true) => { pending = None; baseline = false; }
                Ok(false) => {}
                Err(error) if error.code == StudioErrorCode::Cancelled => {
                    let terminal = source.terminal();
                    let requested_disconnect = terminal.is_none() && owner.task.cancel().is_cancelled();
                    let frame = match terminal {
                        Some(Err(error)) => MetricsFrame::Failure { identity, error },
                        Some(Ok(reason)) => MetricsFrame::Closed { identity, reason },
                        None => MetricsFrame::Closed { identity, reason: FeedClosedReason::Requested },
                    };
                    if let Err(error) = owner.send_control(frame) && !requested_disconnect {
                        owner.task.record_failure(error);
                }
                    return;
                }
                Err(error) => { owner.task.record_failure(error.clone().into());
                    if let Err(error) = owner.send_control(MetricsFrame::Failure { identity, error }) { owner.task.record_failure(error); }
                    return; }
            }
        }
        tokio::select! { biased;
            () = owner.task.cancel().cancelled() => {
                // Explicit cancellation may already have closed the Dart port; no data callback
                // failure is hidden here because admitted sends record theirs above.
                let _ = owner.send_control(MetricsFrame::Closed { identity, reason: FeedClosedReason::Requested });
                return;
            }
            event = source.changed() => match event {
                Ok(StudioMetricsSourceEvent::Sample(sample)) => pending = Some(sample),
                Ok(StudioMetricsSourceEvent::Closed(reason)) => {
                    if let Err(error) = owner.send_control(MetricsFrame::Closed { identity, reason }) { owner.task.record_failure(error); }
                    return;
                }
                Ok(StudioMetricsSourceEvent::Failure(error)) => {
                    if let Err(error) = owner.send_control(MetricsFrame::Failure { identity, error }) { owner.task.record_failure(error); }
                    return;
                }
                Err(error) => {
                    let error = pl_studio_runtime::studio_error_from_anyhow(error);
                    if let Err(error) = owner.send_control(MetricsFrame::Failure { identity, error }) { owner.task.record_failure(error); }
                    return;
                }
            },
            () = changed => {}
        }
    }
}

fn transport_failed() -> BridgeError {
    StudioError::new(StudioErrorCode::Unavailable, "Thread metrics stream sink is unavailable", false).into()
}
