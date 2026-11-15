//! Feed admission, credit and cancellation-safe task/native joins. Historical queries are independent.

use std::{
    future::{Future, poll_fn},
    sync::{Arc, Mutex as SyncMutex},
};

use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::{
    ConversationFeed, ConversationReader, ConversationStateFeed, TimelineReader,
};
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
    content: Option<ContentCapabilities>,
    pub(super) state: SyncMutex<DeliveryState>,
    pub(super) credit: Notify,
    native: Mutex<Option<NativeFeed>>,
    pub(super) timeline: Option<Arc<TimelineReader>>,
    /// Events installation and the whole close operation share this gate; never take it in producer.
    gate: Mutex<()>,
    producer: Mutex<OwnedTaskSlot>,
    /// Installed by registration before publishing the facade. The task waits with a Weak owner,
    /// so merely installing it cannot form an uncancelled Arc self-cycle.
    lifecycle: SyncMutex<Option<Arc<Mutex<OwnedTaskSlot>>>>,
    close_errors: SyncMutex<CloseFailures>,
}

pub(super) struct ContentCapabilities {
    pub(super) reader: ConversationReader,
    pub(super) watches: ContentWatches,
}

pub(super) enum NativeFeed {
    Content(Box<ConversationFeed>),
    State(Box<ConversationStateFeed>),
}

impl NativeFeed {
    pub(super) async fn recv(
        &mut self,
    ) -> Result<Option<crate::api::studio::types::BridgeConversationEvent>, BridgeError> {
        use crate::api::studio::{
            convert::{chat, thread_stream::bridge_thread_update},
            types::BridgeConversationEvent,
        };
        match self {
            Self::Content(feed) => Ok(feed.recv().await?.map(|event| match event {
                pl_studio_runtime::ConversationEvent::Chat { batch } => {
                    BridgeConversationEvent::Chat {
                        batch: Box::new(chat::batch(*batch)),
                    }
                }
                pl_studio_runtime::ConversationEvent::Activity { snapshot } => {
                    BridgeConversationEvent::Activity {
                        snapshot: Box::new(chat::activity((*snapshot).clone())),
                    }
                }
            })),
            Self::State(feed) => feed
                .recv()
                .await?
                .map(|update| {
                    Ok(BridgeConversationEvent::State {
                        update: Box::new(bridge_thread_update(update)?),
                    })
                })
                .transpose(),
        }
    }

    fn request_close(&self) {
        match self {
            Self::Content(feed) => feed.request_close(),
            Self::State(feed) => feed.request_close(),
        }
    }

    async fn close(&mut self) -> Result<(), BridgeError> {
        match self {
            Self::Content(feed) => Ok(feed.close().await?),
            Self::State(feed) => Ok(feed.close().await?),
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
        let content = ContentCapabilities {
            reader: feed.reader().clone(),
            watches: ContentWatches::new(feed.subscription_id()),
        };
        Self::with_native(
            feed.thread_id().to_owned(),
            feed.subscription_id().to_owned(),
            Some(NativeFeed::Content(Box::new(feed))),
            Some(content),
            cancel,
        )
    }

    pub(super) fn timeline(reader: TimelineReader, cancel: CancellationToken) -> Self {
        let content = ContentCapabilities {
            reader: reader.reader().clone(),
            watches: ContentWatches::new(&reader.metadata().reader_id),
        };
        let mut owner = Self::with_native(
            reader.thread_id().to_owned(),
            reader.metadata().reader_id,
            None,
            Some(content),
            cancel,
        );
        owner.timeline = Some(Arc::new(reader));
        owner
    }

    pub(super) fn new_state(feed: ConversationStateFeed, cancel: CancellationToken) -> Self {
        Self::with_native(
            feed.thread_id().to_owned(),
            feed.subscription_id().to_owned(),
            Some(NativeFeed::State(Box::new(feed))),
            None,
            cancel,
        )
    }

    fn with_native(
        thread_id: String,
        subscription_id: String,
        feed: Option<NativeFeed>,
        content: Option<ContentCapabilities>,
        cancel: CancellationToken,
    ) -> Self {
        Self {
            thread_id,
            subscription_id,
            content,
            native: Mutex::new(feed),
            timeline: None,
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

    pub(super) fn content(&self) -> Result<&ContentCapabilities, BridgeError> {
        self.content.as_ref().ok_or_else(|| {
            error(
                StudioErrorCode::InvalidArgument,
                "state feed has no content reader",
            )
        })
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
        if let Some(reader) = &self.timeline {
            reader.request_close();
        }
        self.state.lock().unwrap_or_else(|e| e.into_inner()).closing = true;
        if let Some(content) = &self.content {
            content.watches.request_close_all();
            content.reader.request_close();
        }
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
        if let Some(reader) = &self.timeline {
            reader.close().await?;
        }
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
        let close_content = async {
            if let Some(content) = &self.content {
                let (reader, watches) =
                    tokio::join!(content.reader.close(), content.watches.close_all());
                if let Err(error) = reader {
                    self.remember_failure("read", error.into());
                }
                for (id, error) in watches {
                    self.remember_failure(&format!("content-watch:{id}"), error);
                }
            }
        };
        let (feed, ()) = tokio::join!(self.close_native(), close_content);
        if let Err(error) = feed {
            self.remember_failure("feed", error);
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

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use anyhow::{Context, Result, ensure};
    use tokio::sync::{mpsc, oneshot};

    use super::*;
    use crate::api::studio::handlers::chat::{
        BridgeConversationFeed, producer, tests::Environment,
    };
    use crate::api::studio::types::{BridgeConversationEvent, BridgeReadDemand};

    fn managed(feed: ConversationFeed) -> Arc<ConversationOwner> {
        let owner = Arc::new(ConversationOwner::new(feed, CancellationToken::new()));
        owner.install_lifecycle(|_| {}).unwrap();
        owner
    }

    fn managed_state(feed: ConversationStateFeed) -> Arc<ConversationOwner> {
        let owner = Arc::new(ConversationOwner::new_state(feed, CancellationToken::new()));
        owner.install_lifecycle(|_| {}).unwrap();
        owner
    }

    async fn start_port(owner: &Arc<ConversationOwner>) -> mpsc::Receiver<BridgeConversationFrame> {
        let (tx, rx) = mpsc::channel(2);
        let task_owner = Arc::clone(owner);
        let mut slot = owner.producer.lock().await;
        slot.task = Some(tokio::spawn(async move {
            producer::run_into(task_owner, move |frame| tx.try_send(frame).is_ok()).await
        }));
        rx
    }

    async fn receive(
        rx: &mut mpsc::Receiver<BridgeConversationFrame>,
    ) -> Result<BridgeConversationFrame> {
        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await?
            .context("port closed")
    }

    #[tokio::test]
    async fn paused_producer_does_not_block_original_lease_queries_or_steal_read_close()
    -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let owner = managed(env.feed().await?);
            let facade = BridgeConversationFeed {
                inner: Arc::clone(&owner),
            };
            let mut port = start_port(&owner).await;
            let (sequence, before) = loop {
                let frame = receive(&mut port).await?;
                match frame.event {
                    BridgeConversationEvent::Chat { batch } => {
                        ensure!(
                            batch.placement == crate::api::studio::types::BridgeChatPlacement::Set
                        );
                        break (
                            frame.delivery_sequence,
                            batch.before.context("fixture needs older items")?,
                        );
                    }
                    BridgeConversationEvent::Activity { .. } => {
                        owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                    }
                    event => anyhow::bail!("unexpected initial event: {event:?}"),
                }
            };
            ensure!(
                owner.native.try_lock().is_err(),
                "production pump must hold its native receiver"
            );
            let mut credit = Box::pin(owner.wait_credit());
            ensure!(
                futures::poll!(credit.as_mut()).is_pending(),
                "one unacknowledged batch must exhaust credit"
            );
            ensure!(owner.state.lock().unwrap().inflight_bytes > 0);
            ensure!(owner.acknowledge("another-subscription", sequence).is_err());
            ensure!(
                owner
                    .acknowledge(&owner.subscription_id, sequence + 1)
                    .is_err()
            );
            owner.acknowledge(&owner.subscription_id, sequence - 1)?;
            ensure!(
                futures::poll!(credit.as_mut()).is_pending(),
                "old ACK must not free the outstanding batch"
            );
            let demand = BridgeReadDemand {
                max_items: 2,
                max_bytes: 64 * 1024,
            };
            let page = tokio::time::timeout(
                Duration::from_secs(5),
                facade.load_older(before.clone(), demand),
            )
            .await??;
            ensure!(matches!(
                page.placement,
                crate::api::studio::types::BridgeChatPlacement::Prepend
            ));
            ensure!(!page.entries.is_empty());
            ensure!(
                port.try_recv().is_err(),
                "query must neither ACK nor publish another stream frame"
            );

            // Natural producer retirement owns only the feed. The private original read lease stays usable.
            owner.producer_cancel.cancel();
            ensure!(!credit.await);
            let terminal = receive(&mut port).await?;
            ensure!(terminal.delivery_sequence == sequence);
            ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
            ensure!(
                port.recv().await.is_none(),
                "terminal must be attempted only once"
            );
            let page = facade.load_older(before.clone(), demand).await?;
            ensure!(
                !page.entries.is_empty(),
                "producer exit must not close the facade's read lease"
            );
            facade.close().await?;
            ensure!(owner.is_settled());
            ensure!(owner.native.lock().await.is_none());
            ensure!(facade.load_older(before.clone(), demand).await.is_err());
            ensure!(
                owner
                    .content()?
                    .reader
                    .load_older(&before, chat_demand())
                    .await
                    .is_err()
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    fn chat_demand() -> pl_protocol::ReadDemand {
        pl_protocol::ReadDemand {
            max_items: 2,
            max_bytes: 64 * 1024,
        }
    }

    #[tokio::test]
    async fn close_before_first_frame_uses_sequence_zero_and_joins_every_task() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let owner = managed(env.feed().await?);
            owner.producer_cancel.cancel();
            let mut port = start_port(&owner).await;
            let terminal = receive(&mut port).await?;
            ensure!(terminal.delivery_sequence == 0);
            ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
            ensure!(port.recv().await.is_none());
            owner.close().await?;
            ensure!(owner.is_settled());
            ensure!(owner.producer.lock().await.task.is_none());
            ensure!(owner.native.lock().await.is_none());
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn cancelled_close_wait_retains_join_and_producer_failure_still_closes_read() -> Result<()>
    {
        let env = Environment::new().await?;
        let result = async {
            let owner = managed(env.feed().await?);
            let (release, held) = oneshot::channel();
            owner.producer.lock().await.task = Some(tokio::spawn(async move {
                held.await.map_err(|_| closed())?;
                Ok(())
            }));
            let mut close = Box::pin(owner.close());
            ensure!(futures::poll!(close.as_mut()).is_pending());
            drop(close);
            let mut retry = Box::pin(owner.close());
            ensure!(
                futures::poll!(retry.as_mut()).is_pending(),
                "cancelling a waiter must not abandon the original join"
            );
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("producer was abandoned"))?;
            retry.await?;
            ensure!(owner.is_settled());

            let mut feed = env.feed().await?;
            let before = loop {
                if let Some(pl_studio_runtime::ConversationEvent::Chat { batch }) =
                    feed.recv().await?
                {
                    break batch.before.context("fixture needs older items")?;
                }
            };
            let failed = managed(feed);
            failed
                .content()?
                .reader
                .load_older(&before, chat_demand())
                .await?;
            failed.producer.lock().await.task = Some(tokio::spawn(async {
                panic!("injected producer panic");
            }));
            let diagnostic = failed
                .close()
                .await
                .expect_err("producer panic must propagate");
            ensure!(diagnostic.message.contains("producer"));
            ensure!(
                failed.native.lock().await.is_none(),
                "producer failure must not skip feed cleanup"
            );
            let read_error = failed
                .content()?
                .reader
                .load_older(&before, chat_demand())
                .await
                .expect_err("producer failure must not skip read cleanup");
            ensure!(
                BridgeError::from(read_error).code
                    == crate::api::studio::types::BridgeErrorCode::Cancelled
            );
            ensure!(
                !failed.is_settled(),
                "failure must retain unresolved owner diagnostics"
            );
            ensure!(
                failed.close().await.unwrap_err() == diagnostic,
                "retry must retain the first failure"
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    mod live {
        //! Real provider barriers drive the production FRB producer and native range watch.
        use std::{collections::HashSet, io::Write};

        use super::*;
        use crate::api::studio::{
            handlers::chat::tests::MODEL,
            types::{
                BridgeChatBatch, BridgeChatPlacement, BridgeContentRange, BridgeThreadNotification,
                BridgeThreadSubscriptionUpdate, BridgeTurnState,
            },
        };
        use pl_provider_fixture::{ReplyStage, responses_text_chunks};

        async fn chat(
            owner: &ConversationOwner,
            port: &mut mpsc::Receiver<BridgeConversationFrame>,
            sent: &mut u64,
        ) -> Result<(u64, BridgeChatBatch)> {
            loop {
                let frame = receive(port).await?;
                ensure!(frame.thread_id == owner.thread_id);
                ensure!(frame.subscription_id == owner.subscription_id);
                ensure!(
                    frame.delivery_sequence == *sent + 1,
                    "duplicated or skipped delivery prefix"
                );
                *sent = frame.delivery_sequence;
                match frame.event {
                    BridgeConversationEvent::Activity { .. } => {
                        owner.acknowledge(&owner.subscription_id, *sent)?;
                    }
                    BridgeConversationEvent::Chat { batch } => return Ok((*sent, *batch)),
                    event => anyhow::bail!("unexpected live terminal: {event:?}"),
                }
            }
        }

        async fn next_content(
            owner: &ConversationOwner,
            port: &mut mpsc::Receiver<BridgeConversationFrame>,
            sent: &mut u64,
        ) -> Result<BridgeConversationFrame> {
            let frame = receive(port).await?;
            ensure!(frame.thread_id == owner.thread_id);
            ensure!(frame.subscription_id == owner.subscription_id);
            ensure!(
                frame.delivery_sequence == *sent + 1,
                "duplicated or skipped delivery prefix"
            );
            *sent = frame.delivery_sequence;
            Ok(frame)
        }

        /// State proves business completion and execution removal independently of content retirement.
        pub(super) async fn observe_stopped_execution(
            owner: &ConversationOwner,
            port: &mut mpsc::Receiver<BridgeConversationFrame>,
        ) -> Result<String> {
            let mut sent = 0;
            let mut completed = None;
            let mut executing_turn = None;
            let mut execution_cleared = false;
            loop {
                let frame = next_content(owner, port, &mut sent).await.with_context(|| {
            format!(
                "waiting for State TurnCompleted and execution removal: completed={completed:?}; executing_turn={executing_turn:?}; execution_cleared={execution_cleared}"
            )
        })?;
                let BridgeConversationEvent::State { update } = frame.event else {
                    anyhow::bail!("unexpected event on State feed: {:?}", frame.event);
                };
                match *update {
                    BridgeThreadSubscriptionUpdate::Notification { notification } => {
                        match notification.notification {
                            BridgeThreadNotification::TurnCompleted { turn }
                                if turn.input_id.as_deref() == Some("input-bridge-live") =>
                            {
                                ensure!(
                                    matches!(turn.state, BridgeTurnState::Completed { .. }),
                                    "followup Turn failed: {:?}",
                                    turn.state
                                );
                                ensure!(
                                    completed.replace(turn.id).is_none(),
                                    "duplicate typed terminal"
                                );
                            }
                            BridgeThreadNotification::ThreadRuntimeUpdated { runtime, .. } => {
                                match runtime.execution {
                                    Some(execution) => {
                                        if let Some(turn_id) = execution.turn_id {
                                            executing_turn = Some(turn_id);
                                        }
                                        execution_cleared = false;
                                    }
                                    None => execution_cleared = executing_turn.is_some(),
                                }
                            }
                            BridgeThreadNotification::Lagged { dropped } => {
                                anyhow::bail!("State feed dropped {dropped} notifications");
                            }
                            _ => {}
                        }
                    }
                    BridgeThreadSubscriptionUpdate::Snapshot { .. } => {}
                }
                owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                if execution_cleared && let Some(turn_id) = completed {
                    ensure!(
                        executing_turn.as_ref() == Some(&turn_id),
                        "cleared execution belonged to another Turn"
                    );
                    return Ok(turn_id);
                }
            }
        }

        async fn window(
            facade: &BridgeConversationFeed,
            id: &str,
            stage: &str,
        ) -> Result<crate::api::studio::types::BridgeContentWindow> {
            tokio::time::timeout(
                Duration::from_secs(5),
                facade.next_content_window(id.to_owned()),
            )
            .await
            .map_err(|error| {
                anyhow::anyhow!("{stage}: next_content_window timeout; watch={id}: {error:?}")
            })?
            .map_err(|error| {
                anyhow::anyhow!("{stage}: next_content_window; watch={id}: {error:?}")
            })?
            .with_context(|| format!("{stage}: live watch ended before its window; watch={id}"))
        }

        #[tokio::test]
        async fn live_append_range_watch_replacement_and_retired_facade_keep_original_qualification()
        -> Result<()> {
            let prefix = "prefix 汉字🦀 live ".repeat(64);
            let suffix = " appended tail";
            let replacement = "authoritative replacement 汉字🦀 ".repeat(64);
            let frames = responses_text_chunks(&[&prefix, suffix], "bridge-live", MODEL);
            let head = ReplyStage::new();
            let appended = ReplyStage::new();
            let mut terminal = frames[4..].to_vec();
            terminal[0]["item"]["content"][0]["text"] = replacement.clone().into();
            terminal[1]["response"]["output"][0]["content"][0]["text"] = replacement.clone().into();
            let reply = ReplyStage::staged(
                vec![frames[..3].to_vec(), frames[3..4].to_vec(), terminal],
                &[&head, &appended],
            );
            let env = Environment::with_followup(Some(reply)).await?;
            let state_owner = managed_state(
                env.runtime
                    .open_conversation_state_feed(&env.thread_id)
                    .await?,
            );
            let mut state_port = start_port(&state_owner).await;
            let result = tokio::time::timeout(Duration::from_secs(30), async {
        let content = async {
        let owner = managed(env.feed().await?);
        let facade = BridgeConversationFeed { inner: Arc::clone(&owner) };
        let mut port = start_port(&owner).await;
        let mut sent = 0;
        let (set_seq, initial) = chat(&owner, &mut port, &mut sent).await?;
        ensure!(initial.placement == BridgeChatPlacement::Set);
        ensure!(initial.from_seq.is_none());
        let mut accepted_through = initial.through_seq;
        let before = initial.before.context("nonempty fixture must have an older page")?;
        let old = facade.load_older(before.clone(), BridgeReadDemand {
            max_items: 16, max_bytes: 64 * 1024,
        }).await.map_err(|error| anyhow::anyhow!("history.load_older.initial: {error:?}"))?;
        ensure!(old.placement == BridgeChatPlacement::Prepend && !old.entries.is_empty());
        let historical_record_id = old.entries[0].record_id.clone();
        let mut completed_records = HashSet::new();
        for entry in &initial.entries {
            ensure!(completed_records.insert(entry.record_id.clone()));
        }
        let mut historical = None;
        for entry in old.entries {
            ensure!(completed_records.insert(entry.record_id.clone()));
            if entry.atom.payload.is_some() || !entry.atom.contents.is_empty() {
                let manifest = facade.list_contents(entry.record_id.clone(), None, BridgeReadDemand {
                    max_items: 16, max_bytes: 64 * 1024,
                }).await.map_err(|error| anyhow::anyhow!(
                    "history.list_contents: record_id={}: {error:?}", entry.record_id
                ))?;
                if let Some(manifest_entry) = manifest.entries.into_iter().next() {
                    historical = Some(manifest_entry.reference);
                    break;
                }
            }
        }
        let historical = historical.context("real completed body manifest")?;
        let range = BridgeContentRange { offset: 3, max_bytes: 12 };
        let old_window = facade.read_content(historical.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!("history.read_content.initial: {error:?}"))?;
        ensure!(old_window.sealed && old_window.offset == range.offset && !old_window.bytes.is_empty());
        owner.acknowledge(&owner.subscription_id, set_seq)?;
        env.submit_followup().await?;
        tokio::time::timeout(Duration::from_secs(5), head.wait_reached()).await?;

        // Activity may advance without another completion. ACK all preceding ordinary
        // events; hold the exact Activity snapshot that carries the live body owner.
        let (held_seq, reference, activity_id, turn_id, held_snapshot) = loop {
            let frame = next_content(&owner, &mut port, &mut sent).await
                .context("waiting for the live body Activity")?;
            let sequence = frame.delivery_sequence;
            let snapshot = match frame.event {
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == BridgeChatPlacement::Append
                        && batch.before.is_none()
                        && batch.from_seq == Some(accepted_through)
                        && batch.through_seq > accepted_through);
                    accepted_through = batch.through_seq;
                    for entry in batch.entries {
                        ensure!(completed_records.insert(entry.record_id));
                    }
                    owner.acknowledge(&owner.subscription_id, sequence)?;
                    continue;
                }
                BridgeConversationEvent::Activity { snapshot } => snapshot,
                event => anyhow::bail!("unexpected live event: {event:?}"),
            };
            ensure!(snapshot.revision > 0);
            ensure!(snapshot.completed_through == accepted_through,
                "Activity arrived ahead of or behind the accepted completion prefix");
            let Some(entry) = snapshot.entries.iter().find(|entry|
                entry.atom.kind == crate::api::studio::types::BridgeChatAtomKind::Text
                    && matches!(&entry.atom.lifecycle, crate::api::studio::types::BridgeChatAtomLifecycle::Active { .. })
                    && entry.atom.contents.iter().any(|content|
                        content.role == crate::api::studio::types::BridgeChatContentRole::Body))
            else {
                owner.acknowledge(&owner.subscription_id, sequence)?;
                continue;
            };
            ensure!(snapshot.execution_present);
            let body = entry.atom.contents.iter()
                .find(|content| content.role == crate::api::studio::types::BridgeChatContentRole::Body)
                .context("Activity omitted Body reference")?;
            let identity = match &entry.identity {
                crate::api::studio::types::BridgeActivityIdentity::ModelPart { atom_id } => atom_id,
                other => anyhow::bail!("text body has unexpected activity identity: {other:?}"),
            };
            ensure!(identity == &entry.atom.id);
            // The identity may be published before its first bytes. Observe readiness through
            // the original body watch, not by guessing a valid nonzero offset from Activity.
            let readiness = facade.open_content_watch(
                body.reference.clone(),
                BridgeContentRange { offset: 0, max_bytes: 15 },
            ).await?;
            let prefix_window = loop {
                let next = window(&facade, &readiness, "watch.prefix.readiness").await?;
                if next.available_through >= 15 { break next; }
                ensure!(!next.sealed, "live body sealed before its required prefix");
            };
            ensure!(prefix_window.bytes == prefix.as_bytes()[..15]);
            facade.close_content_watch(readiness).await?;
            let reference = body.reference.clone();
            let activity_id = identity.clone();
            let turn_id = entry.atom.turn_id.clone().context("Activity omitted Turn identity")?;
            break (sequence, reference, activity_id, turn_id, snapshot);
        };
        ensure!(held_snapshot.execution_present && held_snapshot.revision > 0);
        ensure!(owner.native.try_lock().is_err(), "producer owns native recv while credit is held");
        let mut credit = Box::pin(owner.wait_credit());
        ensure!(futures::poll!(credit.as_mut()).is_pending());
        let watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        let first = window(&facade, &watch, "watch.primary.initial").await?;
        ensure!(first.offset == 3 && !first.sealed && first.available_through == prefix.len() as u64);
        ensure!(first.bytes == prefix.as_bytes()[3..15]);
        let cancelled_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        window(&facade, &cancelled_watch, "watch.cancelled.initial").await?;
        let mut waiting = Box::pin(async { facade.next_content_window(cancelled_watch.clone()).await });
        ensure!(futures::poll!(waiting.as_mut()).is_pending(), "unchanged watch should wait");
        facade.request_close_content_watch(cancelled_watch.clone())?;
        let (next, close) = tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(waiting, facade.close_content_watch(cancelled_watch.clone()))
        }).await?;
        ensure!(next?.is_none());
        close?;
        let page = tokio::time::timeout(Duration::from_secs(5), facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 16, max_bytes: 64 * 1024 })).await??;
        ensure!(!page.entries.is_empty());
        let historical_entry = facade.read_completed(
            historical_record_id.clone(),
            BridgeReadDemand { max_items: 1, max_bytes: 64 * 1024 },
        ).await?;
        ensure!(historical_entry.record_id == historical_record_id);
        ensure!(facade.read_content(historical, range.clone()).await?.bytes == old_window.bytes);
        ensure!(port.try_recv().is_err(), "queries/watch must not bypass occupied feed credit");

        head.release();
        tokio::time::timeout(Duration::from_secs(5), appended.wait_reached()).await?;
        let second = window(&facade, &watch, "watch.primary.append").await?;
        ensure!(second.generation == first.generation);
        ensure!(second.available_through == (prefix.len() + suffix.len()) as u64 && !second.sealed);
        ensure!(second.bytes == first.bytes);
        owner.acknowledge(&owner.subscription_id, held_seq)?;
        drop(credit);
        appended.release();
        let final_window = loop {
            let next = window(&facade, &watch, "watch.primary.replacement").await?;
            if next.sealed { break next; }
        };
        ensure!(final_window.bytes == replacement.as_bytes()[3..15]);
        ensure!(final_window.available_through == replacement.len() as u64);
        ensure!(final_window.generation != first.generation);
        ensure!(facade.next_content_window(watch.clone()).await?.is_none());
        facade.close_content_watch(watch).await?;

        let mut completed_body = None;
        let mut retired = false;
        let mut last_activity = None;
        while !retired {
            let frame = next_content(&owner, &mut port, &mut sent).await
                .with_context(|| format!(
                    "waiting for completed body and Activity retirement: completed_body={completed_body:?}; last_activity={last_activity:?}"
                ))?;
            match frame.event {
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == BridgeChatPlacement::Append
                        && batch.before.is_none()
                        && batch.from_seq == Some(accepted_through)
                        && batch.through_seq > accepted_through);
                    accepted_through = batch.through_seq;
                    for entry in batch.entries {
                ensure!(completed_records.insert(entry.record_id.clone()));
                if entry.record_id == match &reference.target {
                    crate::api::studio::types::BridgeContentTarget::Body {
                        owner: crate::api::studio::types::BridgeContentOwner::Item { item_id }, ..
                    } => item_id.clone(),
                    _ => String::new(),
                } {
                    ensure!(entry.atom.id == activity_id);
                    ensure!(entry.atom.turn_id.as_deref() == Some(turn_id.as_str()));
                    completed_body = Some(entry.record_id.clone());
                }
                    }
                }
                BridgeConversationEvent::Activity { snapshot } => {
                    ensure!(snapshot.completed_through == accepted_through);
                    last_activity = Some((snapshot.execution_present, snapshot.entries.len()));
                    retired = !snapshot.entries.iter().any(|entry| {
                        matches!(&entry.identity,
                            crate::api::studio::types::BridgeActivityIdentity::ModelPart { atom_id }
                                if atom_id == &activity_id)
                    });
                    if retired {
                        ensure!(completed_body.is_some(),
                            "Activity member retired before its completion prefix was accepted");
                    }
                }
                event => anyhow::bail!("unexpected completion event: {event:?}"),
            }
            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
            if retired {
                ensure!(completed_body.is_some(), "Activity retired before response completion appeared");
                break;
            }
        }
        ensure!(retired);
        let record_id = completed_body.context("completion record ID")?;
        let point_read = facade.read_completed(record_id.clone(), BridgeReadDemand {
            max_items: 1, max_bytes: 64 * 1024,
        }).await?;
        ensure!(point_read.record_id == record_id && point_read.atom.id == activity_id);

        env.runtime.synchronize_thread_observation(&env.thread_id).await?;
        let replacement_owner = managed(env.feed().await?);
        let replacement_facade = BridgeConversationFeed { inner: replacement_owner };
        ensure!(replacement_facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 2, max_bytes: 64 * 1024 }).await.is_err());
        let late_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        facade.request_close();
        ensure!(facade.next_content_window(late_watch.clone()).await?.is_none());
        facade.close().await?;
        ensure!(owner.is_settled() && owner.native.lock().await.is_none());
        ensure!(owner.producer.lock().await.task.is_none());
        ensure!(facade.read_completed(record_id, BridgeReadDemand {
            max_items: 1, max_bytes: 64 * 1024,
        }).await.is_err());
        ensure!(replacement_facade.read_content(reference, range).await?.bytes == final_window.bytes);
        replacement_facade.close().await?;
        writeln!(std::io::stdout(), "typed Activity→CompletedEntry lifecycle; ACK held at Activity revision {}; independent older/read/watch while credit occupied; final watch close, point read, lease retirement and replacement qualification verified", held_snapshot.revision)?;
        Ok::<_, anyhow::Error>(turn_id)
        };
        let (content, state) = tokio::join!(
            content,
            observe_stopped_execution(&state_owner, &mut state_port),
        );
        let content_turn = content?;
        let state_turn = state?;
        ensure!(content_turn == state_turn, "content and State observed different Turns");
        Ok(())
    }).await.context("live FRB lifecycle exceeded its bounded test budget").and_then(|result| result);
            head.release();
            appended.release();
            let state_close = state_owner.close().await;
            env.finish(result.and(state_close.map_err(anyhow::Error::from)))
                .await
        }
    }

    mod output_limit {
        //! A paced single-item output proves the production FRB producer, facade content mapping and
        //! credit ACKs keep consuming one 256000-byte body while its original Turn and execution run.
        use std::{collections::HashSet, time::Duration};

        use anyhow::{Context, Result, ensure};
        use pl_protocol::{AgentExecutionPhase, ThreadSnapshot, TurnState};
        use pl_provider_fixture::{
            GUI_STREAMING_OUTPUT_REFERENCE_TOKENS, gui_streaming_output_reply,
        };
        use pl_studio_runtime::StudioRuntime;

        use super::*;
        use crate::api::studio::types::{
            BridgeActivityIdentity, BridgeActivitySnapshot, BridgeChatAtomKind,
            BridgeChatAtomLifecycle, BridgeChatContentRole, BridgeChatPlacement,
            BridgeContentOwner, BridgeContentRange, BridgeContentRef, BridgeContentTarget,
            BridgeContentWindow,
        };

        /// `gui_streaming_output_reply(1, 1)` streams one item of 128000 reference tokens as " a" pairs.
        const BODY_BYTES: u64 = (GUI_STREAMING_OUTPUT_REFERENCE_TOKENS * 2) as u64;
        const WINDOW_MAX: u32 = 64 * 1024;

        #[derive(Clone, Debug)]
        struct LiveBodyTarget {
            reference: BridgeContentRef,
            preview_id: String,
            display_id: String,
            turn_id: String,
        }

        impl LiveBodyTarget {
            fn same_identity(&self, other: &LiveBodyTarget) -> bool {
                self.preview_id == other.preview_id
                    && self.reference == other.reference
                    && self.display_id == other.display_id
                    && self.turn_id == other.turn_id
            }
        }

        fn live_body_target(activity: &BridgeActivitySnapshot) -> Result<Option<LiveBodyTarget>> {
            let Some(entry) = activity.entries.iter().find(|entry| {
                entry.atom.kind == BridgeChatAtomKind::Text
                    && matches!(
                        &entry.atom.lifecycle,
                        BridgeChatAtomLifecycle::Active { .. }
                    )
                    && entry
                        .atom
                        .contents
                        .iter()
                        .any(|content| content.role == BridgeChatContentRole::Body)
            }) else {
                return Ok(None);
            };
            let Some(content) = entry
                .atom
                .contents
                .iter()
                .find(|content| content.role == BridgeChatContentRole::Body)
            else {
                return Ok(None);
            };
            ensure!(matches!(
                &content.reference.target,
                BridgeContentTarget::Body {
                    owner: BridgeContentOwner::Item { .. },
                    ..
                }
            ));
            let (atom_id, identity_turn) = match &entry.identity {
                BridgeActivityIdentity::ModelPart { atom_id } => {
                    (atom_id, entry.atom.turn_id.as_ref())
                }
                _ => anyhow::bail!("live Text activity has a non-model identity"),
            };
            let Some(turn_id) = identity_turn else {
                return Ok(None);
            };
            ensure!(atom_id == &entry.atom.id);
            Ok(Some(LiveBodyTarget {
                reference: content.reference.clone(),
                preview_id: atom_id.clone(),
                display_id: atom_id.clone(),
                turn_id: turn_id.clone(),
            }))
        }

        async fn next_frame(
            owner: &ConversationOwner,
            port: &mut mpsc::Receiver<BridgeConversationFrame>,
            sent: &mut u64,
        ) -> Result<BridgeConversationFrame> {
            let frame = receive(port).await?;
            ensure!(frame.thread_id == owner.thread_id);
            ensure!(frame.subscription_id == owner.subscription_id);
            if matches!(
                frame.event,
                BridgeConversationEvent::Failure { .. } | BridgeConversationEvent::Closed
            ) {
                ensure!(
                    frame.delivery_sequence == *sent,
                    "terminal changed the last sent prefix: expected {}, got {}; event={:?}",
                    *sent,
                    frame.delivery_sequence,
                    frame.event
                );
                anyhow::bail!("Main ended before observation completed: {:?}", frame.event);
            }
            ensure!(
                frame.delivery_sequence == *sent + 1,
                "duplicated or skipped sent prefix: expected {}, got {}",
                *sent + 1,
                frame.delivery_sequence
            );
            *sent = frame.delivery_sequence;
            Ok(frame)
        }

        fn running_execution<'a>(snapshot: &'a ThreadSnapshot, turn_id: &str) -> Option<&'a str> {
            let turn = snapshot.active_turn.as_ref()?;
            if turn.id != turn_id || !matches!(turn.state, TurnState::Running(_)) {
                return None;
            }
            let execution = snapshot.runtime.as_ref()?.execution.as_ref()?;
            (execution.phase() == AgentExecutionPhase::Running
                && execution.turn_id() == Some(turn_id))
            .then_some(execution.id())
        }

        async fn next_window(
            facade: &BridgeConversationFeed,
            watch: &str,
            stage: &str,
        ) -> Result<Option<BridgeContentWindow>> {
            tokio::time::timeout(
                Duration::from_secs(5),
                facade.next_content_window(watch.to_owned()),
            )
            .await
            .map_err(|error| {
                anyhow::anyhow!("{stage}: next_content_window timeout; watch={watch}: {error:?}")
            })?
            .map_err(|error| {
                anyhow::anyhow!("{stage}: next_content_window; watch={watch}: {error:?}")
            })
        }

        #[derive(Debug)]
        struct LiveBodyConsumption {
            target: LiveBodyTarget,
            execution_id: String,
            generation: String,
            bytes: u64,
            windows: usize,
            live_reads: usize,
            live_bytes: u64,
            peak_window: usize,
            peak_suffix: usize,
        }

        async fn consume_live_body(
            runtime: &StudioRuntime,
            thread_id: &str,
            facade: &BridgeConversationFeed,
            target: LiveBodyTarget,
        ) -> Result<LiveBodyConsumption> {
            let first = runtime.thread_snapshot(thread_id).await?;
            let execution_id = running_execution(&first, &target.turn_id)
                .context("first live body arrived after its original execution ended")?
                .to_owned();
            let watch = facade
                .open_content_watch(
                    target.reference.clone(),
                    BridgeContentRange {
                        offset: 0,
                        max_bytes: WINDOW_MAX,
                    },
                )
                .await
                .map_err(|error| {
                    anyhow::anyhow!("watch.open: reference={:?}: {error:?}", target.reference)
                })?;
            let result = async {
        let mut cursor = 0;
        let mut available = 0;
        let mut generation = None;
        let mut windows = 0;
        let mut live_reads = 0;
        let mut live_bytes = 0;
        let mut peak_window = 0;
        let mut peak_suffix = 0;
        loop {
            // Fresh hot snapshots bracket the actual read. A pending Main notification alone
            // cannot prove that the original Turn/execution was still running.
            let before = runtime.thread_snapshot(thread_id).await?;
            let window = next_window(facade, &watch, "consume.next")
                .await
                .with_context(|| {
                    format!(
                        "live body before next window: cursor={cursor}; available={available}; \
                         generation={generation:?}; windows={windows}"
                    )
                })?
                .context("content watch ended before a sealed body")?;
            ensure!(window.offset == 0 && window.bytes.len() as u32 <= WINDOW_MAX);
            ensure!(window.bytes.len() as u64 <= window.available_through);
            ensure!(
                window.available_through >= available && window.available_through <= BODY_BYTES,
                "window available_through {} regressed past {available} or exceeded {BODY_BYTES}",
                window.available_through
            );
            ensure!(
                generation
                    .as_ref()
                    .is_none_or(|value| value == &window.generation),
                "append-only body changed generation mid-stream"
            );
            generation = Some(window.generation.clone());
            available = window.available_through;
            let sealed = window.sealed;
            let previous = cursor;
            peak_window = peak_window.max(window.bytes.len());
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            if cursor < window.bytes.len() as u64 {
                cursor = window.bytes.len() as u64;
            }
            // Retain only the cursor/generation; windows are pull-consumed, no second body queue.
            drop(window);
            while cursor < available {
                let request = (available - cursor).min(WINDOW_MAX as u64);
                let suffix = facade
                    .read_content(
                        target.reference.clone(),
                        BridgeContentRange {
                            offset: cursor,
                            max_bytes: request as u32,
                        },
                    )
                    .await
                    .map_err(|error| anyhow::anyhow!("suffix.read offset={cursor}: {error:?}"))?;
                ensure!(suffix.offset == cursor && !suffix.bytes.is_empty());
                ensure!(
                    suffix.bytes.len() as u64 <= request && request <= WINDOW_MAX as u64,
                    "suffix read returned {} bytes over the bounded request {request}",
                    suffix.bytes.len()
                );
                ensure!(suffix.bytes.len() as u64 <= available - cursor);
                ensure!(suffix.available_through >= available && suffix.available_through <= BODY_BYTES);
                ensure!(generation.as_ref() == Some(&suffix.generation));
                let (parts, remainder) = suffix.bytes.as_chunks::<2>();
                ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
                peak_suffix = peak_suffix.max(suffix.bytes.len());
                cursor += suffix.bytes.len() as u64;
            }
            let after = runtime.thread_snapshot(thread_id).await?;
            windows += 1;
            if cursor > previous
                && running_execution(&before, &target.turn_id) == Some(execution_id.as_str())
                && running_execution(&after, &target.turn_id) == Some(execution_id.as_str())
            {
                live_reads += 1;
                live_bytes += cursor - previous;
            }
            if sealed {
                ensure!(
                    cursor == BODY_BYTES,
                    "continuous reader did not consume the complete body: {cursor}/{BODY_BYTES}"
                );
                let end = facade
                    .read_content(
                        target.reference.clone(),
                        BridgeContentRange {
                            offset: cursor,
                            max_bytes: 1,
                        },
                    )
                    .await?;
                ensure!(end.offset == cursor && end.bytes.is_empty() && end.sealed);
                ensure!(end.available_through == BODY_BYTES && generation.as_ref() == Some(&end.generation));
                ensure!(
                    live_reads >= 2 && live_bytes > 0,
                    "no repeated original-running body reads: windows={windows}, live_reads={live_reads}, live_bytes={live_bytes}"
                );
                ensure!(
                    next_window(facade, &watch, "consume.terminal")
                        .await?
                        .is_none(),
                    "watch delivered another window after its sealed EOF"
                );
                break;
            }
        }
        Ok(LiveBodyConsumption {
            execution_id,
            generation: generation.context("sealed body lacked a generation")?,
            target,
            bytes: cursor,
            windows,
            live_reads,
            live_bytes,
            peak_window,
            peak_suffix,
        })
    }
    .await;
            let closed = facade.close_content_watch(watch).await;
            let result =
                result.with_context(|| format!("live content-watch cleanup: {closed:?}"))?;
            closed?;
            Ok(result)
        }

        #[tokio::test]
        async fn output_limit_single_item_streams_body_while_original_turn_runs() -> Result<()> {
            // This current-thread runtime keeps the scoped subscriber on the producer's execution
            // thread too, preserving the original continuity failure without changing global logging.
            let _tracing = tracing::subscriber::set_default(
                tracing_subscriber::fmt()
                    .with_env_filter("conversation_continuity=debug")
                    .with_test_writer()
                    .with_ansi(false)
                    .without_time()
                    .finish(),
            );
            let env =
                Environment::with_output_limit_followup(Some(gui_streaming_output_reply(1, 1)))
                    .await?;
            // The real owner and facade stay strongly referenced outside the bounded observation so
            // success, failure and timeout exits all await the same close instead of async Drop.
            let feed = match env.feed().await {
                Ok(feed) => feed,
                Err(error) => return env.finish(Err(error)).await,
            };
            let owner = managed(feed);
            let facade = BridgeConversationFeed {
                inner: Arc::clone(&owner),
            };
            let mut port = start_port(&owner).await;
            let state_feed = env
                .runtime
                .open_conversation_state_feed(&env.thread_id)
                .await?;
            let state_owner = managed_state(state_feed);
            let mut state_port = start_port(&state_owner).await;
            let mut sent = 0;
            let observation = tokio::time::timeout(Duration::from_secs(120), async {
        // Reliable Main first: the initial real Set must arrive before the followup is submitted.
        let initial = loop {
            let frame = next_frame(&owner, &mut port, &mut sent).await?;
            match frame.event {
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == BridgeChatPlacement::Set);
                    ensure!(batch.from_seq.is_none());
                    break *batch;
                }
                BridgeConversationEvent::Activity { snapshot } => {
                    ensure!(snapshot.completed_through <= i64::MAX as u64);
                    owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                }
                event => anyhow::bail!("unexpected initial event: {event:?}"),
            }
        };
        let mut accepted_through = initial.through_seq;
        let mut item_ids = HashSet::new();
        let mut last_position = None;
        for entry in &initial.entries {
            ensure!(
                item_ids.insert(entry.record_id.clone()),
                "initial Main repeated record"
            );
            let position = entry.completion_seq;
            ensure!(
                last_position.is_none_or(|last| position > last),
                "initial Main changed completion order"
            );
            last_position = Some(position);
        }
        owner.acknowledge(&owner.subscription_id, sent)?;
        env.submit_followup().await?;

        // One oneshot identity handoff; body IO never queues on the reliable Main port.
        let (offer, received) = oneshot::channel::<LiveBodyTarget>();
        let mut offer = Some(offer);
        let runtime = &env.runtime;
        let thread_id = env.thread_id.clone();
        let consume = async {
            let target = received
                .await
                .context("Main never published an original live body")?;
            consume_live_body(runtime, &thread_id, &facade, target).await
        };
        let observe =
            async {
                let result = async {
                let mut retired = false;
                let mut handed_off: Option<LiveBodyTarget> = None;
                let mut appended: Vec<(String, Option<String>)> = Vec::new();
                let mut activity_revision = 0;
                let mut last_activity = None;
                while !retired {
                    let frame = next_frame(&owner, &mut port, &mut sent).await.with_context(|| {
                        format!("content wait: retired={retired}; activity_revision={activity_revision}; last_activity={last_activity:?}")
                    })?;
                    match frame.event {
                        BridgeConversationEvent::Chat { batch } => {
                            let batch = *batch;
                            ensure!(
                                batch.placement == BridgeChatPlacement::Append
                                    && batch.before.is_none()
                                    && batch.from_seq.is_some_and(|from| from < batch.through_seq)
                            );
                            accepted_through = batch.through_seq;
                            ensure!(
                                batch.entries.len() <= 1,
                                "append exceeded the original Main demand"
                            );
                            for item in batch.entries {
                                ensure!(
                                    item_ids.insert(item.record_id.clone()),
                                    "Main repeated completion record {}",
                                    item.record_id
                                );
                                let position = item.completion_seq;
                                let last = last_position
                                    .context("no baseline completion position after initial Set")?;
                                ensure!(
                                    position > last,
                                    "Main Append changed item order: {position} after {last}"
                                );
                                last_position = Some(position);
                                appended.push((item.record_id, item.atom.completion_item_id));
                            }
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        BridgeConversationEvent::Activity { snapshot } => {
                            ensure!(snapshot.revision > activity_revision);
                            ensure!(snapshot.completed_through == accepted_through,
                                "Activity crossed its checked completion prefix");
                            activity_revision = snapshot.revision;
                            last_activity = Some((snapshot.execution_present, snapshot.entries.len()));
                            if let Some(target) = live_body_target(&snapshot)? {
                                if let Some(previous) = &handed_off {
                                    ensure!(
                                        previous.same_identity(&target),
                                        "live Activity identity changed: {previous:?} -> {target:?}"
                                    );
                                } else {
                                    let delivered =
                                        offer.take().context("body handoff offered twice")?;
                                    delivered.send(target.clone()).map_err(|_| {
                                        anyhow::anyhow!("body consumer closed before its target")
                                    })?;
                                    handed_off = Some(target);
                                }
                            }
                            if let Some(target) = &handed_off {
                                retired = !snapshot.entries.iter().any(|entry| {
                                    matches!(&entry.identity,
                                        BridgeActivityIdentity::ModelPart { atom_id }
                                            if atom_id == &target.display_id)
                                });
                                if retired {
                                    ensure!(appended.iter().any(|(id, _)| id == &target.display_id),
                                        "Activity member retired before its completion prefix was accepted");
                                }
                            }
                            owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                        }
                        event => anyhow::bail!("unexpected live event: {event:?}"),
                    }
                }
                Ok((
                    handed_off.context("Main retired without a live body target")?,
                    appended,
                ))
            }
            .await;
                drop(offer);
                result
            };
        // The one-time identity transfer is synchronous; both owners stay joined on any failure.
        let (main, body, state) = tokio::join!(
            observe,
            consume,
            super::live::observe_stopped_execution(&state_owner, &mut state_port),
        );
        let (target, appended) =
            main.with_context(|| format!("continuous body result: {body:?}"))?;
        let body = body?;
        let terminal_turn = state?;
        ensure!(body.bytes == BODY_BYTES);
        ensure!(
            body.target.turn_id == terminal_turn,
            "typed terminal Turn {terminal_turn} differs from the streamed Turn {}",
            body.target.turn_id
        );
        ensure!(
            body.target.same_identity(&target),
            "Main's live identity drifted from the consumed body"
        );
        let matching = appended
            .iter()
            .filter(|(id, _)| id == &body.target.display_id)
            .count();
        ensure!(
            matching == 1,
            "completed Main did not carry the live display item {} exactly once: {appended:?}",
            body.target.display_id
        );
        let mut carrying = 0;
        let mut carrier = None;
        for (id, content_item_id) in &appended {
            let Some(item_id) = content_item_id.as_deref() else {
                continue;
            };
            let manifest = facade
                .list_contents(
                    item_id.to_owned(),
                    None,
                    BridgeReadDemand {
                        max_items: 2,
                        max_bytes: WINDOW_MAX,
                    },
                )
                .await
                .map_err(|error| {
                    anyhow::anyhow!("completion.list_contents item_id={item_id}: {error:?}")
                })?;
            if manifest
                .entries
                .iter()
                .any(|entry| entry.reference == body.target.reference)
            {
                carrying += 1;
                carrier = Some(id.clone());
            }
        }
        ensure!(
            carrying == 1,
            "expected one completed manifest carrying the original reference, saw {carrying}"
        );
        ensure!(
            carrier.as_deref() == Some(body.target.display_id.as_str()),
            "completed manifest owner {carrier:?} differs from the live display id {}",
            body.target.display_id
        );
        // The sealed body is re-readable in bounded windows through the original lease; these
        // post-seal reads stay separate from the original-running byte statistics above.
        let mut sealed_cursor = 0;
        let mut sealed_generation = None;
        while sealed_cursor < BODY_BYTES {
            let request = (BODY_BYTES - sealed_cursor).min(WINDOW_MAX as u64);
            let window = facade
                .read_content(
                    body.target.reference.clone(),
                    BridgeContentRange {
                        offset: sealed_cursor,
                        max_bytes: request as u32,
                    },
                )
                .await
                .map_err(|error| {
                    anyhow::anyhow!("sealed.read offset={sealed_cursor}: {error:?}")
                })?;
            ensure!(
                window.sealed
                    && window.offset == sealed_cursor
                    && !window.bytes.is_empty()
                    && window.available_through == BODY_BYTES
            );
            ensure!(
                window.bytes.len() as u64 <= request && request <= WINDOW_MAX as u64,
                "sealed read returned {} bytes over the bounded request {request}",
                window.bytes.len()
            );
            ensure!(
                sealed_generation
                    .as_ref()
                    .is_none_or(|value| value == &window.generation)
            );
            sealed_generation = Some(window.generation.clone());
            let (parts, remainder) = window.bytes.as_chunks::<2>();
            ensure!(remainder.is_empty() && parts.iter().all(|part| part == b" a"));
            sealed_cursor += window.bytes.len() as u64;
        }
        ensure!(sealed_cursor == BODY_BYTES);
        ensure!(sealed_generation.as_ref() == Some(&body.generation));
        Ok((terminal_turn, item_ids, body, accepted_through))
    })
    .await;
            // Every frame received before close was acknowledged synchronously; the close takes ACK
            // precedence, so already-published trailing frames cannot be acknowledged afterwards.
            let acknowledged_prefix = sent;
            let close = facade.close().await;
            let state_close = state_owner.close().await;
            let settled = owner.is_settled();
            let native_closed = owner.native.lock().await.is_none();
            let producer_joined = owner.producer.lock().await.task.is_none();
            let tail = async {
                let observation = match observation {
                    Ok(result) => result,
                    Err(elapsed) => Err(anyhow::anyhow!(
                        "paced single-item bridge consumer exceeded its observation budget: {elapsed:?}"
                    )),
                };
                let (terminal_turn, mut item_ids, body, mut accepted_through) = observation
                    .with_context(|| {
                        format!(
                            "conversation cleanup: close={close:?}; settled={settled}; \
                 native_closed={native_closed}; producer_joined={producer_joined}"
                        )
                    })?;
                close?;
                ensure!(settled, "conversation owner did not settle after close");
                ensure!(
                    native_closed,
                    "native conversation feed stayed open after close"
                );
                ensure!(producer_joined, "producer task was not joined by close");
                // Closing takes ACK precedence, so already-published trailing frames are validated
                // but not acknowledged.
                let terminal = loop {
                    let frame = receive(&mut port).await?;
                    ensure!(frame.thread_id == owner.thread_id);
                    ensure!(frame.subscription_id == owner.subscription_id);
                    if matches!(
                        frame.event,
                        BridgeConversationEvent::Failure { .. } | BridgeConversationEvent::Closed
                    ) {
                        // The producer terminal reuses the last published sequence by design.
                        ensure!(frame.delivery_sequence == sent);
                        ensure!(
                            matches!(frame.event, BridgeConversationEvent::Closed),
                            "Main failed during close: {:?}",
                            frame.event
                        );
                        break frame;
                    }
                    ensure!(
                        frame.delivery_sequence == sent + 1,
                        "duplicated or skipped trailing prefix: expected {}, got {}",
                        sent + 1,
                        frame.delivery_sequence
                    );
                    sent = frame.delivery_sequence;
                    match frame.event {
                        BridgeConversationEvent::Chat { batch } => {
                            ensure!(
                                batch.placement == BridgeChatPlacement::Append
                                    && batch.before.is_none()
                                    && batch.from_seq.is_some_and(|from| from < batch.through_seq)
                            );
                            accepted_through = batch.through_seq;
                            for item in batch.entries {
                                ensure!(
                                    item_ids.insert(item.record_id.clone()),
                                    "trailing Main repeated completion {}",
                                    item.record_id
                                );
                            }
                        }
                        BridgeConversationEvent::Activity { snapshot } => {
                            ensure!(snapshot.revision > 0);
                            ensure!(snapshot.completed_through == accepted_through);
                        }
                        event => anyhow::bail!("unexpected trailing event: {event:?}"),
                    }
                };
                ensure!(
                    port.recv().await.is_none(),
                    "terminal must be attempted only once"
                );
                {
                    let state = owner.state.lock().unwrap();
                    ensure!(
                        terminal.delivery_sequence == state.sent && state.sent == sent,
                        "terminal sequence {} differs from published {} or drained {sent}",
                        terminal.delivery_sequence,
                        state.sent
                    );
                    ensure!(
                        state.acknowledged == acknowledged_prefix,
                        "real ACK watermark {} diverged from the acknowledged prefix {acknowledged_prefix}",
                        state.acknowledged
                    );
                    eprintln!(
                        "delivery credit: acknowledged={}, published={}, drained={}",
                        state.acknowledged, state.sent, sent
                    );
                }
                eprintln!(
                    "continuous bridge body: execution={}, turn={}, display={}, bytes={}, windows={}, \
             original_running_reads={}, original_running_bytes={}, peak_window_bytes={}, \
             peak_suffix_bytes={}",
                    body.execution_id,
                    terminal_turn,
                    body.target.display_id,
                    body.bytes,
                    body.windows,
                    body.live_reads,
                    body.live_bytes,
                    body.peak_window,
                    body.peak_suffix,
                );
                Ok(())
            };
            let tail = tail.await.and(state_close.map_err(anyhow::Error::from));
            env.finish(tail).await
        }
    }

    mod state {
        //! Real independent native feeds drive the shared production bridge producer.
        use super::*;
        use crate::api::studio::{
            handlers::chat::{BridgeConversationStateFeed, tests::MODEL},
            types::{
                BridgeErrorCode, BridgeThreadNotification, BridgeThreadSubscriptionUpdate,
                BridgeTurnState,
            },
        };
        use pl_provider_fixture::{Reply, responses_text};

        #[tokio::test]
        async fn content_without_ack_does_not_block_state_runtime_or_share_ack_credit() -> Result<()>
        {
            let env = Environment::with_followup(Some(Reply::Sse(responses_text(
                "Independent state completed.",
                "bridge-state-followup",
                MODEL,
            ))))
            .await?;
            let result = tokio::time::timeout(Duration::from_secs(15), async {
                let content = managed(env.feed().await?);
                let state = managed_state(
                    env.runtime
                        .open_conversation_state_feed(&env.thread_id)
                        .await?,
                );
                ensure!(
                    state.content().is_err(),
                    "state must not own a content reader"
                );
                ensure!(content.subscription_id != state.subscription_id);
                let mut content_port = start_port(&content).await;
                let mut state_port = start_port(&state).await;
                let first_content = receive(&mut content_port).await?;
                ensure!(matches!(
                    first_content.event,
                    BridgeConversationEvent::Chat { .. }
                ));
                ensure!(first_content.delivery_sequence == 1);
                let first_state = receive(&mut state_port).await?;
                ensure!(first_state.thread_id == env.thread_id);
                ensure!(first_state.subscription_id == state.subscription_id);
                ensure!(first_state.delivery_sequence == 1);
                ensure!(matches!(
                    first_state.event,
                    BridgeConversationEvent::State { update }
                        if matches!(*update, BridgeThreadSubscriptionUpdate::Snapshot { .. })
                ));

                // Neither another feed's identity nor a future prefix can release this feed's credit.
                ensure!(
                    state
                        .acknowledge(&content.subscription_id, 1)
                        .unwrap_err()
                        .code
                        == BridgeErrorCode::InvalidArgument
                );
                ensure!(
                    content
                        .acknowledge(&state.subscription_id, 1)
                        .unwrap_err()
                        .code
                        == BridgeErrorCode::InvalidArgument
                );
                ensure!(
                    state
                        .acknowledge(&state.subscription_id, 2)
                        .unwrap_err()
                        .code
                        == BridgeErrorCode::InvalidArgument
                );
                let mut blocked = Box::pin(state.wait_credit());
                ensure!(futures::poll!(blocked.as_mut()).is_pending());
                state.acknowledge(&state.subscription_id, 0)?;
                ensure!(futures::poll!(blocked.as_mut()).is_pending());
                state.acknowledge(&state.subscription_id, 1)?;
                state.acknowledge(&state.subscription_id, 1)?;
                ensure!(blocked.await);
                let mut content_blocked = Box::pin(content.wait_credit());
                ensure!(futures::poll!(content_blocked.as_mut()).is_pending());
                ensure!(content_port.try_recv().is_err());

                env.submit_followup().await?;
                let mut sent = 1;
                let mut runtime_seen = false;
                loop {
                    let frame = receive(&mut state_port).await?;
                    ensure!(frame.subscription_id == state.subscription_id);
                    ensure!(frame.thread_id == state.thread_id);
                    ensure!(frame.delivery_sequence == sent + 1);
                    sent = frame.delivery_sequence;
                    let BridgeConversationEvent::State { update } = frame.event else {
                        anyhow::bail!("state producer emitted non-State data");
                    };
                    let mut completed = false;
                    if let BridgeThreadSubscriptionUpdate::Notification { notification } = *update {
                        match notification.notification {
                            BridgeThreadNotification::ThreadRuntimeUpdated { .. } => {
                                runtime_seen = true
                            }
                            BridgeThreadNotification::TurnCompleted { turn }
                                if turn.input_id.as_deref() == Some("input-bridge-live") =>
                            {
                                ensure!(matches!(turn.state, BridgeTurnState::Completed { .. }));
                                completed = true;
                            }
                            _ => {}
                        }
                    }
                    if completed {
                        ensure!(
                            runtime_seen,
                            "no runtime update crossed the blocked content feed"
                        );
                        break;
                    }
                    state.acknowledge(&state.subscription_id, sent)?;
                }
                ensure!(futures::poll!(content_blocked.as_mut()).is_pending());
                ensure!(
                    content_port.try_recv().is_err(),
                    "state ACK released content credit"
                );
                {
                    let credit = content.state.lock().unwrap();
                    ensure!(credit.sent == 1 && credit.acknowledged == 0);
                }
                // Both producers now wait for independent ACKs. Close must emit terminals and join
                // without acquiring credit or acknowledging either outstanding ordinary frame.
                let (content_close, state_close) = tokio::join!(content.close(), state.close());
                content_close?;
                state_close?;
                ensure!(!content_blocked.await);
                for (owner, port, sequence) in [
                    (&content, &mut content_port, 1),
                    (&state, &mut state_port, sent),
                ] {
                    let terminal = receive(port).await?;
                    ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
                    ensure!(terminal.delivery_sequence == sequence);
                    ensure!(port.recv().await.is_none());
                    ensure!(owner.is_settled());
                    ensure!(owner.native.lock().await.is_none());
                    ensure!(owner.producer.lock().await.task.is_none());
                }
                Ok(())
            })
            .await
            .context("independent bridge feeds timed out")
            .and_then(|result| result);
            env.finish(result).await
        }

        #[tokio::test]
        async fn state_close_before_listen_and_with_available_credit_retains_native_join()
        -> Result<()> {
            let env = Environment::new().await?;
            let result = async {
                let unopened = managed_state(
                    env.runtime
                        .open_conversation_state_feed(&env.thread_id)
                        .await?,
                );
                let facade = BridgeConversationStateFeed {
                    inner: Arc::clone(&unopened),
                };
                facade.close().await?;
                facade.close().await?;
                ensure!(unopened.is_settled());
                ensure!(unopened.native.lock().await.is_none());
                ensure!(unopened.producer.lock().await.task.is_none());
                ensure!(
                    facade
                        .acknowledge("wrong".into(), u64::MAX)
                        .unwrap_err()
                        .code
                        == BridgeErrorCode::Cancelled
                );

                let idle = managed_state(
                    env.runtime
                        .open_conversation_state_feed(&env.thread_id)
                        .await?,
                );
                let mut port = start_port(&idle).await;
                let first = receive(&mut port).await?;
                idle.acknowledge(&idle.subscription_id, first.delivery_sequence)?;
                ensure!(idle.wait_credit().await);
                tokio::time::timeout(Duration::from_secs(5), idle.close()).await??;
                ensure!(idle.is_settled());
                ensure!(idle.native.lock().await.is_none());
                ensure!(idle.producer.lock().await.task.is_none());
                Ok(())
            }
            .await;
            env.finish(result).await
        }
    }

    mod timeline {
        use super::*;
        #[tokio::test]
        async fn cursor_reader_queries_and_close_do_not_use_producer_credit() -> Result<()> {
            let env = Environment::new().await?;
            let result: Result<()> = async {
                let native = env
                    .runtime
                    .open_timeline_reader(
                        &env.thread_id,
                        6,
                        1,
                        pl_protocol::ReadDemand {
                            max_items: 2,
                            max_bytes: 64 * 1024,
                        },
                    )
                    .await?;
                let owner = Arc::new(ConversationOwner::timeline(
                    native,
                    CancellationToken::new(),
                ));
                owner.install_lifecycle(|_| {})?;
                let reader = owner.timeline.as_ref().context("timeline capability")?;
                let first = reader.next(reader.metadata().initial_cursor).await?;
                ensure!(first.history.placement == pl_protocol::HistoryPlacement::Set);
                ensure!(first == reader.next(first.after.clone()).await?);
                ensure!(owner.native.lock().await.is_none());
                owner.content()?.reader.read_business_refs().await?;
                owner.close().await?;
                ensure!(owner.is_settled());
                ensure!(reader.next(first.next).await.is_err());
                Ok(())
            }
            .await;
            env.finish(result).await
        }
    }
}
