//! Feed admission, credit and cancellation-safe task/native joins. Historical queries are independent.
use std::sync::{Arc, Mutex as SyncMutex};

use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::ConversationFeed;
use tokio::sync::{Mutex, Notify};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::api::studio::types::{BridgeConversationFrame, BridgeError};
use crate::frb_generated::StreamSink;

pub(crate) struct ConversationOwner {
    pub(super) thread_id: String,
    pub(crate) subscription_id: String,
    pub(super) cancel: CancellationToken,
    pub(super) state: SyncMutex<DeliveryState>,
    pub(super) credit: Notify,
    native: Mutex<Option<ConversationFeed>>,
    /// Events installation and the whole close operation share this gate; never take it in producer.
    gate: Mutex<()>,
    producer: Mutex<OwnedTaskSlot>,
    /// Installed by registration before publishing the facade. The task waits with a Weak owner,
    /// so merely installing it cannot form an uncancelled Arc self-cycle.
    lifecycle: SyncMutex<Option<Arc<Mutex<OwnedTaskSlot>>>>,
    close_error: SyncMutex<Option<BridgeError>>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(super) struct DeliveryState {
    pub(super) closing: bool,
    started: bool,
    pub(super) sent: u64,
    acknowledged: u64,
    settled: bool,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct OwnedTaskSlot {
    task: Option<JoinHandle<Result<(), BridgeError>>>,
    /// Retained even after a JoinError so later close callers never poll a completed handle or lose
    /// the first failure. Native close still runs after any owned task failure.
    outcome: Option<Result<(), BridgeError>>,
}

impl ConversationOwner {
    pub(super) fn new(feed: ConversationFeed, cancel: CancellationToken) -> Self {
        Self {
            thread_id: feed.thread_id().to_owned(),
            subscription_id: feed.subscription_id().to_owned(),
            native: Mutex::new(Some(feed)),
            cancel,
            state: SyncMutex::new(DeliveryState::default()),
            credit: Notify::new(),
            gate: Mutex::new(()),
            producer: Mutex::new(OwnedTaskSlot::default()),
            lifecycle: SyncMutex::new(None),
            close_error: SyncMutex::new(None),
        }
    }

    /// Called once while the opening registry holds its publication lock. Even immediate shutdown
    /// cannot complete unregistration before this task and the owner are both installed there.
    pub(crate) fn install_lifecycle(
        self: &Arc<Self>,
        on_settled: impl FnOnce(&str) + Send + 'static,
    ) -> Result<(), BridgeError> {
        let mut slot = self.lifecycle.lock().unwrap_or_else(|e| e.into_inner());
        if slot.is_some() {
            return Err(error(
                StudioErrorCode::Conflict,
                "conversation lifecycle is already registered",
            ));
        }
        let owner = Arc::downgrade(self);
        let cancel = self.cancel.clone();
        let task = tokio::spawn(async move {
            cancel.cancelled().await;
            let Some(owner) = owner.upgrade() else {
                return Ok(());
            };
            // This path only joins the data producer, never its own lifecycle handle. At successful
            // unregistration every capability and owned producer is already retired; only this
            // synchronous terminal bookkeeping and returning the retained result remain.
            let result = owner.finish_close().await;
            if result.is_ok() {
                on_settled(&owner.subscription_id);
            }
            result
        });
        *slot = Some(Arc::new(Mutex::new(OwnedTaskSlot {
            task: Some(task),
            outcome: None,
        })));
        Ok(())
    }

    pub(super) async fn start(
        self: &Arc<Self>,
        sink: StreamSink<BridgeConversationFrame>,
    ) -> Result<(), BridgeError> {
        self.ensure_open()?;
        let _gate = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(closed()),
            gate = self.gate.lock() => gate,
        };
        let mut producer = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(closed()),
            producer = self.producer.lock() => producer,
        };
        {
            let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            self.check_open(&state)?;
            if state.started {
                return Err(error(
                    StudioErrorCode::Conflict,
                    "conversation events can only be registered once",
                ));
            }
            state.started = true;
        }
        // No cancellation point between spawn and retained installation. The producer owns the only
        // sink; there is no unjoined second pump and no mpsc payload queue ahead of the native port.
        let owner = Arc::clone(self);
        // Panic/early exit must also wake the lifecycle owner, not just normal pump cancellation.
        let exit_cancel = self.cancel.clone().drop_guard();
        producer.task = Some(tokio::spawn(async move {
            let _exit_cancel = exit_cancel;
            super::producer::run(owner, sink).await
        }));
        Ok(())
    }

    pub(super) fn acknowledge(&self, subscription: &str, sequence: u64) -> Result<(), BridgeError> {
        {
            let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            self.check_open(&state)?;
            if subscription != self.subscription_id {
                return Err(BridgeError::invalid_argument(
                    "ACK belongs to another conversation subscription",
                ));
            }
            if sequence > state.sent {
                return Err(BridgeError::invalid_argument(
                    "ACK exceeds the sent conversation prefix",
                ));
            }
            state.acknowledged = state.acknowledged.max(sequence);
        }
        self.credit.notify_one();
        Ok(())
    }

    pub(crate) fn request_close(&self) {
        self.state.lock().unwrap_or_else(|e| e.into_inner()).closing = true;
        self.cancel.cancel();
    }

    pub(super) fn ensure_open(&self) -> Result<(), BridgeError> {
        self.check_open(&self.state.lock().unwrap_or_else(|e| e.into_inner()))
    }

    fn check_open(&self, state: &DeliveryState) -> Result<(), BridgeError> {
        if state.closing || self.cancel.is_cancelled() {
            Err(closed())
        } else {
            Ok(())
        }
    }

    /// Reserve capacity before native receive and conversion. Only the single producer sends, while
    /// ACK can only increase credit, so capacity cannot be stolen between this check and publication.
    pub(super) async fn wait_credit(&self) -> bool {
        loop {
            let notified = self.credit.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.cancel.is_cancelled() {
                return false;
            }
            {
                let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                if state.closing {
                    return false;
                }
                if state.sent - state.acknowledged < 2 {
                    return true;
                }
            }
            tokio::select! {
                biased;
                () = self.cancel.cancelled() => return false,
                () = notified => {},
            }
        }
    }

    pub(super) async fn native(&self) -> tokio::sync::MutexGuard<'_, Option<ConversationFeed>> {
        self.native.lock().await
    }

    /// Cancellation-safe native close: keep the original feed in its slot across every await.
    pub(super) async fn close_native(&self) -> Result<(), BridgeError> {
        let mut slot = self.native.lock().await;
        if let Some(feed) = slot.as_mut() {
            feed.request_close();
            feed.close().await?;
            slot.take();
        }
        Ok(())
    }

    pub(crate) async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        let lifecycle = self
            .lifecycle
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .ok_or_else(|| {
                error(
                    StudioErrorCode::Internal,
                    "conversation lifecycle was not registered",
                )
            })?;
        let outcome = self
            .join_task(
                &lifecycle,
                "conversation lifecycle task did not stop cleanly",
            )
            .await;
        if outcome.is_err() {
            // A panicked lifecycle cannot continue its original cleanup. Retain its failure, but
            // retry the same resource slots (not a replacement task), under the same close gate.
            // Cancellation here still leaves the remaining slots and error in the registry owner.
            self.finish_close().await?;
        }
        outcome
    }

    async fn finish_close(&self) -> Result<(), BridgeError> {
        self.request_close();
        let _gate = self.gate.lock().await;
        let _ = self
            .join_task(
                &self.producer,
                "conversation producer task did not stop cleanly",
            )
            .await;
        if let Err(error) = self.close_native().await {
            self.remember_failure(error);
        }
        if let Some(error) = self
            .close_error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
        {
            return Err(error);
        }
        self.state.lock().unwrap_or_else(|e| e.into_inner()).settled = true;
        Ok(())
    }

    async fn join_task(
        &self,
        task: &Mutex<OwnedTaskSlot>,
        message: &str,
    ) -> Result<(), BridgeError> {
        let mut slot = task.lock().await;
        if let Some(task) = slot.task.as_mut() {
            let result = match task.await {
                Ok(result) => result,
                Err(_) => Err(error(StudioErrorCode::Internal, message)),
            };
            slot.task = None;
            slot.outcome = Some(result);
        }
        if let Some(Err(error)) = &slot.outcome {
            self.remember_failure(error.clone());
        }
        slot.outcome.clone().unwrap_or(Ok(()))
    }

    fn remember_failure(&self, error: BridgeError) {
        self.close_error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get_or_insert(error);
    }

    pub(crate) fn is_settled(&self) -> bool {
        self.state.lock().unwrap_or_else(|e| e.into_inner()).settled
    }
}

pub(super) fn closed() -> BridgeError {
    error(StudioErrorCode::Cancelled, "conversation feed is closed")
}

pub(super) fn error(code: StudioErrorCode, message: &str) -> BridgeError {
    StudioError::new(code, message, false).into()
}
