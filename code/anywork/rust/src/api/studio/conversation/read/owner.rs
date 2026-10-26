//! Transport-only lifetime for concrete execution scopes; actual queries stay in native ReadCalls.
use super::super::identity::BridgeReadScopeIdentity;
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use pl_protocol::studio::{FeedCloseOutcome, StudioError};
use pl_studio_runtime::StudioRuntime;
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;

pub(super) use crate::read_owner::ExecutionRead;

struct Owner<S> {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<S>>>,
    cleanup: tokio::sync::Mutex<()>,
}

#[flutter_rust_bridge::frb(ignore)]
pub(super) struct ReadHandle<S: ExecutionRead> {
    owner: Arc<Owner<S>>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeReadScopeIdentity,
}

struct Opening<S: ExecutionRead>(Option<Arc<Owner<S>>>);
impl<S: ExecutionRead> Drop for Opening<S> {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub(super) async fn open_read<S, F>(
    open: impl FnOnce(StudioRuntime) -> F + Send + 'static,
) -> Result<ReadHandle<S>, BridgeError>
where
    S: ExecutionRead,
    F: Future<Output = anyhow::Result<S>> + Send + 'static,
{
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(Owner {
        task: task.clone(),
        source: Mutex::new(None),
        cleanup: tokio::sync::Mutex::new(()),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let work = owner.clone();
    if let Err(error) = task.start(async move {
        let source = match open(bridge.studio.clone()).await {
            Ok(source) => Arc::new(source),
            Err(error) => {
                work.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *work
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
        let result = work.task.admit(|| {
            source.ensure_open()?;
            Ok(source.identity())
        });
        if result.is_err() {
            work.request_close();
        }
        if opened.send(result).is_err() {
            work.request_close();
        }
        work.task.cancel().cancelled().await;
        work.close_source().await;
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = ready
        .await
        .map_err(|_| BridgeError::from(StudioError::internal()))??;
    let read = ReadHandle {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(read)
}

impl<S: ExecutionRead> ReadHandle<S> {
    pub(super) fn identity(&self) -> BridgeReadScopeIdentity {
        self.identity.clone()
    }
    pub(super) fn query<F>(&self, query: impl FnOnce(&S) -> F) -> Result<F, BridgeError> {
        self.owner.task.admit(|| {
            let source = self
                .owner
                .source
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
                .ok_or_else(closed)?;
            source.ensure_open()?;
            Ok(query(&source))
        })
    }
    pub(super) fn request_close(&self) {
        self.owner.request_close();
    }
    pub(super) async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let _ = self.owner.task.wait_stopped().await;
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
}
impl<S: ExecutionRead> Drop for ReadHandle<S> {
    fn drop(&mut self) {
        self.request_close();
    }
}
impl<S: ExecutionRead> Owner<S> {
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
        let _cleanup = self.cleanup.lock().await;
        let source = self
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let Some(source) = source else {
            return;
        };
        let issues = match source.close().await.outcome {
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
impl<S: ExecutionRead> TypedFeedResource for Owner<S> {
    fn release_after_join(&self) {
        self.source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }
}
