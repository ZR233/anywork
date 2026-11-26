//! Managed FRB pull handle for a Native conversation's typed observation and bounded reads.

use std::future::Future;

use pl_lifecycle::{Managed, ManagedResource};
use pl_studio_runtime::{ConversationFeed, StudioError, StudioErrorCode};
use tokio::sync::{Mutex, RwLock};

use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::presentation,
    subscription::{
        error::{close_error, open_error},
        factory::BridgeObservationFactory,
    },
    types::{
        BridgeBodyRef, BridgeBodyWindow, BridgeConversationEvent, BridgeError,
        BridgeLiveStatusSnapshot, BridgeSessionDetailKind, BridgeSessionDetailWindow,
        BridgeSessionMetaSnapshot, BridgeTimelinePatch, BridgeWorkGroupMember,
    },
};

struct ConversationResource {
    feed: ConversationFeed,
    next: Mutex<()>,
    operations: RwLock<()>,
}

impl ConversationResource {
    // The read guard lasts through the query and its conversion. Closing seals admission with
    // the feed token and acquires the write guard before joining the backend and its reader.
    async fn query<T>(
        &self,
        operation: impl Future<Output = Result<T, BridgeError>>,
    ) -> Result<T, BridgeError> {
        let cancel = self.feed.cancellation_token();
        tokio::select! {
            biased;
            () = cancel.cancelled() => Err(StudioError::new(
                StudioErrorCode::StaleRevision,
                "ConversationFeed is closed or retired",
                false,
            ).into()),
            result = async {
                let _operation = self.operations.read().await;
                operation.await
            } => result,
        }
    }

    async fn next_event(&self) -> Result<Option<BridgeConversationEvent>, BridgeError> {
        let cancel = self.feed.cancellation_token();
        tokio::select! {
            biased;
            () = cancel.cancelled() => Ok(None),
            result = async {
                let _operation = self.operations.read().await;
                if cancel.is_cancelled() {
                    return Ok(None);
                }
                let _next = self.next.try_lock().map_err(|_| {
                    BridgeError::from(StudioError::new(
                        StudioErrorCode::Busy,
                        "A conversation next event is already in flight",
                        true,
                    ))
                })?;
                let event = self.feed.next_event().await;
                Ok(event.map(presentation::conversation_event).transpose()?)
            } => result,
        }
    }
}

impl ManagedResource for ConversationResource {
    type Error = BridgeError;

    fn request_close(&self) {
        self.feed.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        let _operations = self.operations.write().await;
        self.feed.close().await;
        Ok(())
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConversationFeed {
    inner: Managed<ConversationResource>,
}

pub async fn open_conversation_feed(
    thread_id: String,
    initial_limit: u32,
) -> Result<BridgeConversationFeed, BridgeError> {
    active_bridge()
        .await?
        .observation_factory
        .open_conversation(thread_id, initial_limit)
        .await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_conversation(
        &self,
        thread_id: String,
        initial_limit: u32,
    ) -> Result<BridgeConversationFeed, BridgeError> {
        let source = self.source.clone();
        let inner = self
            .scope
            .open("conversation-feed", move |_| async move {
                let feed = source
                    .open_conversation_feed_with_maintenance(&thread_id, initial_limit)
                    .await?;
                Ok(ConversationResource {
                    feed,
                    next: Mutex::new(()),
                    operations: RwLock::new(()),
                })
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeConversationFeed { inner })
    }
}

impl BridgeConversationFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.inner.get().feed.thread_id().to_owned()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn live_status_snapshot(&self) -> BridgeLiveStatusSnapshot {
        presentation::live_status_snapshot(self.inner.get().feed.live_status_snapshot())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn session_meta_snapshot(&self) -> Result<BridgeSessionMetaSnapshot, BridgeError> {
        Ok(presentation::session_meta_snapshot(
            self.inner.get().feed.session_meta_snapshot(),
        )?)
    }

    /// The first event is the backend's initial Timeline Reset. A single consumer pulls in order.
    pub async fn next_event(&self) -> Result<Option<BridgeConversationEvent>, BridgeError> {
        self.inner.get().next_event().await
    }

    pub async fn load_older(
        &self,
        cursor: String,
        limit: u32,
    ) -> Result<BridgeTimelinePatch, BridgeError> {
        let resource = self.inner.get();
        resource
            .query(async {
                Ok(presentation::timeline_patch(
                    resource.feed.load_older(cursor, limit).await?,
                )?)
            })
            .await
    }

    pub async fn load_work_group_members(
        &self,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
    ) -> Result<Vec<BridgeWorkGroupMember>, BridgeError> {
        let resource = self.inner.get();
        resource
            .query(async {
                Ok(resource
                    .feed
                    .load_work_group_members(after_seq, before_seq)
                    .await?
                    .into_iter()
                    .map(presentation::work_group_member)
                    .collect())
            })
            .await
    }

    pub async fn read_body_window(
        &self,
        reference: BridgeBodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeBodyWindow, BridgeError> {
        let resource = self.inner.get();
        resource
            .query(async {
                Ok(presentation::body_window(
                    resource
                        .feed
                        .read_body_window(
                            &presentation::runtime_body_ref(reference),
                            offset,
                            max_bytes,
                        )
                        .await?,
                ))
            })
            .await
    }

    pub async fn read_session_detail(
        &self,
        kind: BridgeSessionDetailKind,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeSessionDetailWindow, BridgeError> {
        let resource = self.inner.get();
        resource
            .query(async {
                Ok(presentation::session_detail_window(
                    resource.feed.read_session_detail(
                        presentation::runtime_session_detail_kind(kind),
                        offset,
                        max_bytes,
                    )?,
                ))
            })
            .await
    }

    pub async fn reset_to_latest(&self, limit: u32) -> Result<BridgeTimelinePatch, BridgeError> {
        let resource = self.inner.get();
        resource
            .query(async {
                Ok(presentation::timeline_patch(
                    resource.feed.reset_to_latest(limit).await?,
                )?)
            })
            .await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.get().request_close();
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(close_error)
    }
}
