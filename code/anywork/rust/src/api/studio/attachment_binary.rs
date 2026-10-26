//! Mechanical FRB mapping of the same registered native file pin; no binary cache or feed.
use std::sync::{Arc, Mutex};

use pl_protocol::studio::{AttachmentBinaryIdentity, AttachmentBinaryTarget, FeedCloseOutcome};
use pl_studio_runtime::attachment_binary::StudioAttachmentBinaryRead;
use tokio::sync::oneshot;

use super::bridge_runtime::installed_bridge;
use super::subscription::BridgeTaskRegistry;
use super::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use super::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeAttachmentBinaryTarget {
    Draft {
        draft_id: String,
    },
    Thread {
        thread_id: String,
        attachment_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAttachmentBinaryIdentity {
    pub scope_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
    pub target: BridgeAttachmentBinaryTarget,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAttachmentBinaryChunk {
    pub offset: i64,
    pub bytes: Vec<u8>,
    pub next_offset: Option<i64>,
}

struct BinaryOwner {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<StudioAttachmentBinaryRead>>>,
    cleanup: tokio::sync::Mutex<()>,
}

/// Opaque over the original scope, including late opening and real blocking IO join.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAttachmentBinaryRead {
    owner: Arc<BinaryOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeAttachmentBinaryIdentity,
    byte_length: i64,
}

struct Opening(Option<Arc<BinaryOwner>>);
impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

pub async fn open_draft_binary(
    draft_id: String,
) -> Result<BridgeAttachmentBinaryRead, BridgeError> {
    open(AttachmentBinaryTarget::Draft { draft_id }).await
}

pub async fn open_thread_binary(
    thread_id: String,
    attachment_id: String,
) -> Result<BridgeAttachmentBinaryRead, BridgeError> {
    open(AttachmentBinaryTarget::Thread {
        thread_id,
        attachment_id,
    })
    .await
}

async fn open(target: AttachmentBinaryTarget) -> Result<BridgeAttachmentBinaryRead, BridgeError> {
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(BinaryOwner {
        task: task.clone(),
        source: Mutex::new(None),
        cleanup: tokio::sync::Mutex::new(()),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        let source = match target {
            AttachmentBinaryTarget::Draft { draft_id } => {
                bridge.studio.open_draft_binary(draft_id).await
            }
            AttachmentBinaryTarget::Thread {
                thread_id,
                attachment_id,
            } => {
                bridge
                    .studio
                    .open_thread_binary(thread_id, attachment_id)
                    .await
            }
        };
        let source = match source {
            Ok(source) => Arc::new(source),
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *producer
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
        let reply = producer.task.admit(|| {
            source.ensure_open()?;
            Ok((source.identity(), source.byte_length()))
        });
        if reply.is_err() {
            producer.request_close();
        }
        if opened.send(reply).is_err() {
            producer.request_close();
        }
        producer.task.cancel().cancelled().await;
        producer.close_source().await;
    }) {
        owner.request_close();
        return Err(error);
    }
    let (identity, byte_length) = ready
        .await
        .map_err(|_| BridgeError::from(pl_protocol::studio::StudioError::internal()))??;
    let read = BridgeAttachmentBinaryRead {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
        byte_length,
    };
    opening.0.take();
    Ok(read)
}

impl BridgeAttachmentBinaryRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeAttachmentBinaryIdentity {
        self.identity.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn byte_length(&self) -> i64 {
        self.byte_length
    }

    pub async fn read(
        &self,
        offset: i64,
        max_bytes: Option<i64>,
    ) -> Result<BridgeAttachmentBinaryChunk, BridgeError> {
        let query = self.owner.task.admit(|| {
            let source = self
                .owner
                .source
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
                .ok_or_else(closed)?;
            source.ensure_open()?;
            Ok(source.read(offset, max_bytes))
        })?;
        let chunk = query.await?;
        Ok(BridgeAttachmentBinaryChunk {
            offset: chunk.offset,
            bytes: chunk.bytes,
            next_offset: chunk.next_offset,
        })
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let _ = self.owner.task.wait_stopped().await;
        // The real opening/first close joined before a retry can inspect the retained source.
        self.owner.close_source().await;
        let issues = self.owner.task.close_issues();
        let outcome = if issues.is_empty() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues }
        };
        Ok(BridgeFeedCloseReport {
            feed_id: self.identity.scope_id.clone(),
            outcome,
        })
    }

    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}

impl Drop for BridgeAttachmentBinaryRead {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl BinaryOwner {
    fn request_close(&self) {
        self.task.signal_cancel();
        let source = self
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(source) = source {
            source.request_close();
        }
    }

    async fn close_source(&self) {
        // Serializes replacement of the original native close report, never file IO on a sync lock.
        let _cleanup = self.cleanup.lock().await;
        let source = self
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let Some(source) = source else {
            return;
        };
        let issues = match source.retry_close().await.outcome {
            FeedCloseOutcome::Clean => {
                self.source
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take();
                Vec::new()
            }
            FeedCloseOutcome::Unresolved { issues } => issues.into_iter().map(Into::into).collect(),
        };
        self.task.replace_cleanup_issues(issues);
    }
}

#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for BinaryOwner {
    fn release_after_join(&self) {
        let source = self
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        drop(source);
    }
}

impl From<AttachmentBinaryIdentity> for BridgeAttachmentBinaryIdentity {
    fn from(identity: AttachmentBinaryIdentity) -> Self {
        Self {
            scope_id: identity.scope_id,
            runtime_epoch: identity.runtime_epoch,
            incarnation: identity.incarnation,
            target: match identity.target {
                AttachmentBinaryTarget::Draft { draft_id } => {
                    BridgeAttachmentBinaryTarget::Draft { draft_id }
                }
                AttachmentBinaryTarget::Thread {
                    thread_id,
                    attachment_id,
                } => BridgeAttachmentBinaryTarget::Thread {
                    thread_id,
                    attachment_id,
                },
            },
        }
    }
}
