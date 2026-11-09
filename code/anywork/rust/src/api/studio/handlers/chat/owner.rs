//! Feed admission, credit and cancellation-safe task/native joins. Historical queries are independent.
#[cfg(test)]
mod tests;
use std::{
    future::{Future, poll_fn},
    sync::{Arc, Mutex as SyncMutex},
};

use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::{ConversationEvent, ConversationFeed, ConversationReader, TimelineFeed};
use tokio::sync::{Mutex, Notify};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::{close_failures::CloseFailures, content_watch::ContentWatches};
use crate::api::studio::types::{BridgeConversationFrame, BridgeError};
use crate::frb_generated::StreamSink;

pub(crate) struct ConversationOwner {
    pub(super) thread_id: String,
    pub(crate) subscription_id: String,
    pub(super) cancel: CancellationToken,
    pub(super) producer_cancel: CancellationToken,
    /// Same original lease, captured before the native feed can be locked by the producer.
    pub(super) reader: ConversationReader,
    pub(super) watches: ContentWatches,
    pub(super) state: SyncMutex<DeliveryState>,
    pub(super) credit: Notify,
    native: Mutex<Option<NativeFeed>>,
    /// Events installation and the whole close operation share this gate; never take it in producer.
    gate: Mutex<()>,
    producer: Mutex<OwnedTaskSlot>,
    /// Installed by registration before publishing the facade. The task waits with a Weak owner,
    /// so merely installing it cannot form an uncancelled Arc self-cycle.
    lifecycle: SyncMutex<Option<Arc<Mutex<OwnedTaskSlot>>>>,
    close_errors: SyncMutex<CloseFailures>,
}

/// Only native receive/close differ; credit, read admission and joins have one owner.
#[flutter_rust_bridge::frb(ignore)]
pub(super) enum NativeFeed {
    Conversation(Box<ConversationFeed>),
    Timeline(Box<TimelineFeed>),
}

impl NativeFeed {
    fn thread_id(&self) -> &str {
        match self {
            Self::Conversation(feed) => feed.thread_id(),
            Self::Timeline(feed) => feed.thread_id(),
        }
    }

    fn subscription_id(&self) -> &str {
        match self {
            Self::Conversation(feed) => feed.subscription_id(),
            Self::Timeline(feed) => feed.subscription_id(),
        }
    }

    fn reader(&self) -> &ConversationReader {
        match self {
            Self::Conversation(feed) => feed.reader(),
            Self::Timeline(feed) => feed.reader(),
        }
    }

    pub(super) async fn recv(&mut self) -> anyhow::Result<Option<ConversationEvent>> {
        match self {
            Self::Conversation(feed) => feed.recv().await,
            Self::Timeline(feed) => feed.receive().await.map(Some),
        }
    }

    fn request_close(&self) {
        match self {
            Self::Conversation(feed) => feed.request_close(),
            Self::Timeline(feed) => feed.request_close(),
        }
    }

    async fn close_observation(&mut self) -> anyhow::Result<()> {
        match self {
            Self::Conversation(feed) => feed.close().await,
            Self::Timeline(feed) => feed.close().await,
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(super) struct DeliveryState {
    pub(super) closing: bool,
    started: bool,
    pub(super) sent: u64,
    acknowledged: u64,
    pub(super) inflight_bytes: usize,
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
        Self::from_native(NativeFeed::Conversation(Box::new(feed)), cancel)
    }

    pub(super) fn timeline(feed: TimelineFeed, cancel: CancellationToken) -> Self {
        Self::from_native(NativeFeed::Timeline(Box::new(feed)), cancel)
    }

    fn from_native(feed: NativeFeed, cancel: CancellationToken) -> Self {
        Self {
            thread_id: feed.thread_id().to_owned(),
            subscription_id: feed.subscription_id().to_owned(),
            reader: feed.reader().clone(),
            watches: ContentWatches::new(feed.subscription_id()),
            native: Mutex::new(Some(feed)),
            producer_cancel: cancel.child_token(),
            cancel,
            state: SyncMutex::new(DeliveryState::default()),
            credit: Notify::new(),
            gate: Mutex::new(()),
            producer: Mutex::new(OwnedTaskSlot::default()),
            lifecycle: SyncMutex::new(None),
            close_errors: SyncMutex::new(CloseFailures::default()),
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
        // Panic/early exit revokes only producer delivery. Read retirement and retained cleanup
        // still belong to explicit facade close (or the opening runtime's shutdown).
        let exit_cancel = self.producer_cancel.clone().drop_guard();
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
            if state.acknowledged == state.sent {
                state.inflight_bytes = 0;
            }
        }
        self.credit.notify_one();
        Ok(())
    }

    pub(crate) fn request_close(&self) {
        self.state.lock().unwrap_or_else(|e| e.into_inner()).closing = true;
        self.watches.request_close_all();
        self.reader.request_close();
        self.cancel.cancel();
    }

    pub(super) fn ensure_read_open(&self) -> Result<(), BridgeError> {
        if self.cancel.is_cancelled()
            || self.state.lock().unwrap_or_else(|e| e.into_inner()).closing
        {
            Err(closed())
        } else {
            Ok(())
        }
    }

    pub(super) fn ensure_open(&self) -> Result<(), BridgeError> {
        self.check_open(&self.state.lock().unwrap_or_else(|e| e.into_inner()))
    }

    fn check_open(&self, state: &DeliveryState) -> Result<(), BridgeError> {
        if state.closing || self.producer_cancel.is_cancelled() {
            Err(closed())
        } else {
            Ok(())
        }
    }

    /// Reserve capacity before native receive and conversion. Only the single producer sends, while
    /// ACK can only increase credit, so capacity cannot be stolen between this check and publication.
    pub(super) async fn wait_credit(&self) -> bool {
        let mut recorded_wait = false;
        loop {
            let notified = self.credit.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.producer_cancel.is_cancelled() {
                return false;
            }
            {
                let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                if state.closing {
                    return false;
                }
                if state.sent == state.acknowledged {
                    return true;
                }
            }
            let waiting = poll_fn(|cx| {
                let polled = notified.as_mut().poll(cx);
                if polled.is_pending() && !recorded_wait {
                    let counters = {
                        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                        (!state.closing
                            && !self.producer_cancel.is_cancelled()
                            && state.sent - state.acknowledged == 1)
                            .then_some((state.sent, state.acknowledged))
                    };
                    if let Some((sent, acknowledged)) = counters {
                        // Observe the original registered wait after an actual Pending poll.
                        // Logging never takes credit, consumes another notification or holds state.
                        tracing::debug!(
                            target: "anywork::conversation_credit",
                            credit_wait = %serde_json::json!({
                                "subscriptionId": self.subscription_id.as_str(),
                                "sent": sent,
                                "acknowledged": acknowledged,
                            }),
                            "producer_credit_wait_pending"
                        );
                        recorded_wait = true;
                    }
                }
                polled
            });
            tokio::select! {
                biased;
                () = self.producer_cancel.cancelled() => return false,
                () = waiting => {},
            }
        }
    }

    pub(super) async fn native(&self) -> tokio::sync::MutexGuard<'_, Option<NativeFeed>> {
        self.native.lock().await
    }

    /// Retires only production; the original read lease belongs to finish_close independently.
    /// Keep the original feed in its slot across every await so cancellation loses no join.
    pub(super) async fn close_native(&self) -> Result<(), BridgeError> {
        let mut slot = self.native.lock().await;
        if let Some(feed) = slot.as_mut() {
            feed.request_close();
            feed.close_observation().await?;
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
                "lifecycle",
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
                "producer",
                "conversation producer task did not stop cleanly",
            )
            .await;
        // Neither a feed failure nor a read failure may skip the other responsibility.
        // Both futures borrow retained slots, so cancelling this join loses no owner.
        let (feed, reader, watches) = tokio::join!(
            self.close_native(),
            self.reader.close(),
            self.watches.close_all(),
        );
        for (resource, result) in [("feed", feed), ("read", reader.map_err(BridgeError::from))] {
            if let Err(error) = result {
                self.remember_failure(resource, error);
            }
        }
        for (id, error) in watches {
            self.remember_failure(&format!("content-watch:{id}"), error);
        }
        if let Some(error) = self
            .close_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .outcome()
        {
            return Err(error);
        }
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        state.inflight_bytes = 0;
        state.settled = true;
        Ok(())
    }

    async fn join_task(
        &self,
        task: &Mutex<OwnedTaskSlot>,
        resource: &str,
        message: &str,
    ) -> Result<(), BridgeError> {
        let mut slot = task.lock().await;
        if let Some(task) = slot.task.as_mut() {
            let result = match task.await {
                Ok(result) => result,
                Err(_) => {
                    let failure = error(StudioErrorCode::Internal, message);
                    self.remember_failure(resource, failure.clone());
                    Err(failure)
                }
            };
            slot.task = None;
            slot.outcome = Some(result);
        }
        if resource != "lifecycle"
            && let Some(Err(error)) = &slot.outcome
        {
            self.remember_failure(resource, error.clone());
        }
        slot.outcome.clone().unwrap_or(Ok(()))
    }

    pub(super) fn remember_failure(&self, resource: &str, error: BridgeError) {
        self.close_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .record(resource, error);
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
