//! One combined conversation observation, a single FRB push consumer, and independent read queries.
mod owner;
mod producer;

use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::{
    BridgeConversationFrame, BridgeError, BridgeTimelineCompletionCursor,
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
    resume_after: Option<BridgeTimelineCompletionCursor>,
) -> Result<BridgeConversationFeed, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let feed = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(closed()),
        feed = bridge.studio.open_conversation_feed(
            &thread_id,
            resume_after.map(crate::api::studio::convert::timeline_content::protocol_completion_cursor),
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
