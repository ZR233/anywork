//! 关机进度订阅：与 runtime 生命周期共享同一次 shutdown 序列。

use super::{
    BridgeEventSubscription, BridgeSubscriptionInner, BridgeSubscriptionKind,
    BridgeSubscriptionReceiver, error::open_error, shutdown_progress_scope, task::OwnedTaskSlot,
};
use crate::api::studio::bridge_runtime::current_bridge;
use crate::api::studio::types::{BridgeError, BridgeShutdownProgress};
use crate::frb_generated::StreamSink;
use pl_studio_runtime::StudioShutdownProgress;

/// Creates an independently owned shutdown-progress subscription, including during retry.
///
/// The caller cancels this handle before cancelling its Dart stream, so failed shutdown
/// does not leave stream cancellation waiting for a future progress event.
///
/// When no runtime is installed yet, this returns an immediately-closed (empty) stream without
/// triggering initialization or surfacing a spurious `NotInitialized`. A second instance whose
/// startup failed has no owner and must observe a benign "no progress" stream, not a fake error.
pub async fn subscribe_shutdown_progress() -> Result<BridgeEventSubscription, BridgeError> {
    let source = current_bridge().map(|bridge| bridge.studio.clone());
    let inner = shutdown_progress_scope()
        .handle()
        .open("shutdownProgress", move |cancel| async move {
            let events = match source {
                Some(source) => source.subscribe_shutdown_progress().await,
                None => {
                    // `broadcast::channel(1)` with the sender dropped hands back a receiver that is already
                    // closed, so the shutdown stream ends immediately without owning any runtime.
                    let (sender, receiver) = tokio::sync::broadcast::channel(1);
                    drop(sender);
                    receiver
                }
            };
            Ok(BridgeSubscriptionInner {
                kind: BridgeSubscriptionKind::Shutdown,
                cancel,
                producer_task: tokio::sync::Mutex::new(OwnedTaskSlot::default()),
                sink_task: tokio::sync::Mutex::new(OwnedTaskSlot::default()),
                receiver: tokio::sync::Mutex::new(Some(BridgeSubscriptionReceiver::Shutdown(
                    events,
                ))),
            })
        })
        .await
        .map_err(open_error)?;
    Ok(BridgeEventSubscription {
        inner,
        _scope: None,
    })
}

impl BridgeEventSubscription {
    /// Opens this shutdown subscription once. Cancellation closes the native sink.
    ///
    /// # Errors
    /// Rejects another subscription kind or a second stream consumer.
    pub async fn shutdown_stream(
        &self,
        sink: StreamSink<BridgeShutdownProgress>,
    ) -> Result<(), BridgeError> {
        let inner = self.inner.get();
        if !matches!(inner.kind, BridgeSubscriptionKind::Shutdown) {
            return Err(BridgeError::invalid_argument(
                "non-shutdown subscription cannot open a shutdown stream",
            ));
        }
        let mut events = match inner.receiver.lock().await.take() {
            Some(BridgeSubscriptionReceiver::Shutdown(events)) => events,
            _ => {
                return Err(BridgeError::invalid_argument(
                    "shutdown stream can only be opened once on a shutdown subscription",
                ));
            }
        };
        let cancel = inner.cancel.clone();
        inner.attach_sink(async move {
            loop {
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => break,
                    progress = events.recv() => match progress {
                        Ok(progress) => {
                            let stopped = progress.is_stopped();
                            if sink.add(bridge_shutdown_progress(progress)).is_err() || stopped { break; }
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                    }
                }
            }
            Ok(())
        }).await;
        Ok(())
    }
}

fn bridge_shutdown_progress(progress: StudioShutdownProgress) -> BridgeShutdownProgress {
    match progress {
        StudioShutdownProgress::StoppingSubscriptions(_) => {
            BridgeShutdownProgress::StoppingSubscriptions
        }
        StudioShutdownProgress::CancellingTurns(_) => BridgeShutdownProgress::CancellingTurns,
        StudioShutdownProgress::FlushingPersistence(progress) => {
            BridgeShutdownProgress::FlushingPersistence {
                pending_commits: progress.pending_commits(),
            }
        }
        StudioShutdownProgress::StoppingAgents(_) => BridgeShutdownProgress::StoppingAgents,
        StudioShutdownProgress::StoppingMcp(_) => BridgeShutdownProgress::StoppingMcp,
        StudioShutdownProgress::StoppingLsp(_) => BridgeShutdownProgress::StoppingLsp,
        StudioShutdownProgress::Stopped(_) => BridgeShutdownProgress::Stopped,
    }
}
