//! One combined conversation observation, a single FRB push consumer, and independent read queries.
mod close_failures;
mod content_watch;
mod owner;
mod producer;
#[cfg(test)]
mod tests;

use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::chat;
use crate::api::studio::types::{
    BridgeChatBatch, BridgeChatScope, BridgeContentManifestPage, BridgeContentRange,
    BridgeContentRef, BridgeContentWindow, BridgeConversationFrame, BridgeCurrentCollectionPage,
    BridgeCurrentCollectionRef, BridgeError, BridgeReadDemand,
};
use crate::frb_generated::StreamSink;

pub(crate) use owner::ConversationOwner;
use owner::closed;

/// Opaque owner of one captured native feed. Dropping this facade requests cancellation; the opening
/// registry retains the real owner until close confirms every task, query and native observation.
pub struct BridgeConversationFeed {
    inner: Arc<ConversationOwner>,
}

/// Opens exactly one native combined feed, without a second tail or a separately rebuilt baseline.
/// Cancellation before publication drops the native feed through its own RAII boundary.
pub async fn open_conversation_feed(
    thread_id: String,
    scope: BridgeChatScope,
    demand: BridgeReadDemand,
) -> Result<BridgeConversationFeed, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let feed = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(closed()),
        feed = bridge.studio.open_conversation_feed(
            &thread_id,
            chat::scope(scope),
            chat::demand(demand),
        ) => feed?,
    };
    let inner = Arc::new(ConversationOwner::new(feed, cancel));
    let opening = inner.cancel.clone().drop_guard();
    // Register the owner and its cancellation-driven lifecycle task in one synchronous publication
    // boundary. The opening guard cancels any installed responsibility if publication fails.
    bridge
        .subscriptions
        .register_conversation(&inner, &bridge.shutdown)?;
    drop(opening.disarm());
    Ok(BridgeConversationFeed { inner })
}

impl BridgeConversationFeed {
    /// Registers one bounded range observation on this facade's original read lease.
    pub async fn open_content_watch(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<String, BridgeError> {
        self.inner.ensure_read_open()?;
        self.inner
            .watches
            .open(
                &self.inner.reader,
                &self.inner.cancel,
                chat::protocol_content_ref(reference),
                chat::range(range),
            )
            .await
    }

    /// Pulls at most one window. Overlapping reads of the same watch are rejected, not queued.
    pub async fn next_content_window(
        &self,
        watch_id: String,
    ) -> Result<Option<BridgeContentWindow>, BridgeError> {
        self.inner.watches.next(&watch_id).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.inner.watches.request_close(&watch_id)
    }

    /// Cancels first, then joins the retained native watch before releasing its identity/capacity.
    pub async fn close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.inner.watches.close(&watch_id).await
    }

    /// Queries share the original read lease, never the producer's native receive/credit mutex.
    pub async fn load_older(
        &self,
        before: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeChatBatch, BridgeError> {
        self.inner.ensure_read_open()?;
        let batch = self
            .inner
            .reader
            .load_older(&before, chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        let batch = chat::batch(batch);
        if tracing::enabled!(target: "conversation_work", tracing::Level::DEBUG) {
            use crate::frb_generated::SseEncode as _;
            let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
            batch.clone().sse_encode(&mut serializer);
            tracing::debug!(
                target: "conversation_work",
                thread_id = %self.inner.thread_id,
                trace_id = %self.inner.subscription_id,
                // A normal success uses the same SSE action byte as StreamSink::add.
                frb_encoded_bytes = serializer.cursor.get_ref().len() + 1,
                "FRB page returned"
            );
        }
        Ok(batch)
    }

    /// Reads a bounded ordinary page before an observed completion position.
    /// This continuation is independent of the original H0 history cursor and feed credit.
    pub async fn read_before(
        &self,
        completion_seq: u64,
        before: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeChatBatch, BridgeError> {
        self.inner.ensure_read_open()?;
        let batch = self
            .inner
            .reader
            .read_before(completion_seq, before.as_deref(), chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::batch(batch))
    }

    /// Reads the same bounded ordinary window including its observed completion anchor.
    pub async fn read_at(
        &self,
        completion_seq: u64,
        before: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeChatBatch, BridgeError> {
        self.inner.ensure_read_open()?;
        let batch = self
            .inner
            .reader
            .read_at(completion_seq, before.as_deref(), chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::batch(batch))
    }

    pub async fn list_contents(
        &self,
        item_id: String,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeContentManifestPage, BridgeError> {
        self.inner.ensure_read_open()?;
        let page = self
            .inner
            .reader
            .list_contents(&item_id, continuation.as_deref(), chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::manifest(page))
    }

    pub async fn read_content(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<BridgeContentWindow, BridgeError> {
        self.inner.ensure_read_open()?;
        let window = self
            .inner
            .reader
            .read_content(&chat::protocol_content_ref(reference), chat::range(range))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::window(window))
    }

    pub async fn page_current(
        &self,
        reference: BridgeCurrentCollectionRef,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentCollectionPage, BridgeError> {
        self.inner.ensure_read_open()?;
        let page = self
            .inner
            .reader
            .page_current(
                &chat::protocol_collection_ref(reference),
                continuation.as_deref(),
                chat::demand(demand),
            )
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::collection_page(page))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.inner.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn subscription_id(&self) -> String {
        self.inner.subscription_id.clone()
    }

    /// Installs the sole producer and sink atomically with respect to close. A second consumer is a
    /// Conflict; a sealed handle always returns Cancelled first. Producer exit drops the sink.
    pub async fn events(
        &self,
        sink: StreamSink<BridgeConversationFrame>,
    ) -> Result<(), BridgeError> {
        self.inner.start(sink).await
    }

    /// Acknowledges the sent contiguous prefix. Wrong identity and future sequences are rejected;
    /// repeated old prefixes are idempotent. Closing takes precedence over argument checks.
    #[flutter_rust_bridge::frb(sync)]
    pub fn acknowledge(
        &self,
        subscription_id: String,
        delivery_sequence: u64,
    ) -> Result<(), BridgeError> {
        self.inner.acknowledge(&subscription_id, delivery_sequence)
    }

    /// Seals admission and wakes credit and receive waits without issuing business cancellation.
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    /// Joins retained work and closes native capabilities. Cancelled close waits can be repeated;
    /// failed closes retain the original owner and diagnostic in the opening registry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await
    }
}

impl Drop for BridgeConversationFeed {
    fn drop(&mut self) {
        self.inner.request_close();
    }
}
