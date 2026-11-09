//! GUI presentation facade over the original conversation owner and read lease.

use std::sync::Arc;

use super::{BridgeConversationFeed, ConversationOwner, closed};
use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::{chat, presentation},
    types::*,
};
use crate::frb_generated::StreamSink;

pub struct BridgeTimelineFeed {
    conversation: BridgeConversationFeed,
}

pub async fn open_timeline_feed(
    thread_id: String,
    initial_demand: BridgeReadDemand,
) -> Result<BridgeTimelineFeed, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let feed = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(closed()),
        feed = bridge.studio.open_timeline_feed(&thread_id, chat::demand(initial_demand)) => feed?,
    };
    let inner = Arc::new(ConversationOwner::timeline(feed, cancel));
    let opening = inner.cancel.clone().drop_guard();
    bridge
        .subscriptions
        .register_conversation(&inner, &bridge.shutdown)?;
    drop(opening.disarm());
    Ok(BridgeTimelineFeed {
        conversation: BridgeConversationFeed { inner },
    })
}

impl BridgeTimelineFeed {
    /// Atomic content tools retain the original completion reader; GUI history uses load_older.
    pub async fn load_completed_older(
        &self,
        before: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeChatBatch, BridgeError> {
        self.conversation.load_older(before, demand).await
    }

    pub async fn load_older(
        &self,
        before: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeTimelineBatch, BridgeError> {
        let owner = &self.conversation.inner;
        owner.ensure_read_open()?;
        let batch = owner
            .content()?
            .reader
            .load_timeline_older(&before, chat::demand(demand))
            .await?;
        owner.ensure_read_open()?;
        presentation::batch(batch)
    }

    pub async fn load_live_older(
        &self,
        before: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeLiveDisplayWindow, BridgeError> {
        let owner = &self.conversation.inner;
        owner.ensure_read_open()?;
        let window = owner
            .content()?
            .reader
            .load_live_older(&before, chat::demand(demand))
            .await?;
        owner.ensure_read_open()?;
        Ok(presentation::live_window(window))
    }

    pub async fn open_display_members(
        &self,
        reference: BridgeDisplayBlockRef,
        window: BridgeDisplayMemberWindow,
        demand: BridgeReadDemand,
    ) -> Result<BridgeDisplayMembers, BridgeError> {
        let owner = &self.conversation.inner;
        owner.ensure_read_open()?;
        let id = owner
            .content()?
            .watches
            .open_members(
                &owner.content()?.reader,
                &owner.cancel,
                presentation::protocol_block_ref(reference),
                presentation::member_window(window),
                chat::demand(demand),
            )
            .await?;
        Ok(BridgeDisplayMembers {
            owner: Arc::clone(owner),
            id,
        })
    }

    pub async fn read_completed(
        &self,
        record_id: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCompletedEntry, BridgeError> {
        self.conversation.read_completed(record_id, demand).await
    }

    pub async fn read_business_refs(&self) -> Result<BridgeThreadBusinessRefs, BridgeError> {
        self.conversation.read_business_refs().await
    }

    pub async fn list_contents(
        &self,
        item_id: String,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeContentManifestPage, BridgeError> {
        self.conversation
            .list_contents(item_id, continuation, demand)
            .await
    }

    pub async fn read_content(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<BridgeContentWindow, BridgeError> {
        self.conversation.read_content(reference, range).await
    }

    pub async fn page_current(
        &self,
        reference: BridgeCurrentCollectionRef,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentCollectionPage, BridgeError> {
        self.conversation
            .page_current(reference, continuation, demand)
            .await
    }

    pub async fn open_content_watch(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<String, BridgeError> {
        self.conversation.open_content_watch(reference, range).await
    }

    pub async fn next_content_window(
        &self,
        watch_id: String,
    ) -> Result<Option<BridgeContentWindow>, BridgeError> {
        self.conversation.next_content_window(watch_id).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.conversation.request_close_content_watch(watch_id)
    }

    pub async fn close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.conversation.close_content_watch(watch_id).await
    }

    pub async fn events(
        &self,
        sink: StreamSink<BridgeConversationFrame>,
    ) -> Result<(), BridgeError> {
        self.conversation.events(sink).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.conversation.thread_id()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn subscription_id(&self) -> String {
        self.conversation.subscription_id()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn acknowledge(
        &self,
        subscription_id: String,
        delivery_sequence: u64,
    ) -> Result<(), BridgeError> {
        self.conversation
            .acknowledge(subscription_id, delivery_sequence)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.conversation.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.conversation.close().await
    }
}

/// Fixed member window registered with the same read owner as content observations.
pub struct BridgeDisplayMembers {
    owner: Arc<ConversationOwner>,
    id: String,
}

impl BridgeDisplayMembers {
    pub async fn next(&self) -> Result<Option<BridgeDisplayMemberPage>, BridgeError> {
        self.owner.content()?.watches.next_members(&self.id).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) -> Result<(), BridgeError> {
        self.owner.content()?.watches.request_close(&self.id)
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.owner.content()?.watches.close(&self.id).await
    }
}

impl Drop for BridgeDisplayMembers {
    fn drop(&mut self) {
        // The conversation registry retains the exact slot and its join obligation.
        if let Ok(content) = self.owner.content() {
            let _ = content.watches.request_close(&self.id);
        }
    }
}
