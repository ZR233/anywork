//! Opaque ownership only; concrete queries and the sole scope/call registry remain in runtime.
use std::future::Future;
use std::sync::{Arc, Mutex};

use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::models::{FeedCloseReport, ProductReadScopeIdentity, StudioAccountTemplatesRead,
    StudioError, StudioModelCatalogRead};
use pl_protocol::studio::FeedCloseOutcome;
use tokio::sync::oneshot;

use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use super::super::identity::BridgeProductReadScopeIdentity;

#[flutter_rust_bridge::frb(ignore)]
pub(super) trait ModelsRead: Send + Sync + 'static {
    fn identity(&self) -> ProductReadScopeIdentity;
    fn ensure_open(&self) -> Result<(), StudioError>;
    fn request_close(&self);
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send;
}

impl ModelsRead for StudioModelCatalogRead {
    fn identity(&self) -> ProductReadScopeIdentity { StudioModelCatalogRead::identity(self) }
    fn ensure_open(&self) -> Result<(), StudioError> { StudioModelCatalogRead::ensure_open(self) }
    fn request_close(&self) { StudioModelCatalogRead::request_close(self); }
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send { StudioModelCatalogRead::close(self) }
}

impl ModelsRead for StudioAccountTemplatesRead {
    fn identity(&self) -> ProductReadScopeIdentity { StudioAccountTemplatesRead::identity(self) }
    fn ensure_open(&self) -> Result<(), StudioError> { StudioAccountTemplatesRead::ensure_open(self) }
    fn request_close(&self) { StudioAccountTemplatesRead::request_close(self); }
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send { StudioAccountTemplatesRead::close(self) }
}

struct ReadOwner<S> {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<S>>>,
}

#[flutter_rust_bridge::frb(ignore)]
pub(super) struct ModelsReadHandle<S: ModelsRead> {
    owner: Arc<ReadOwner<S>>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeProductReadScopeIdentity,
}

// Sending the oneshot is not handoff: the caller may disappear after the send but before taking
// the queued result. Only returning the actual opaque transfers this cancellation responsibility.
struct Opening<S: ModelsRead>(Option<Arc<ReadOwner<S>>>);

impl<S: ModelsRead> Drop for Opening<S> {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 { owner.request_close(); }
    }
}

/// Register before any await, and never drop an admitted runtime opening to cancel it. A lost
/// reply still leaves its source in the registered owner until the original close truly joins.
#[flutter_rust_bridge::frb(ignore)]
pub(super) async fn open_read<S, F>(open: impl FnOnce(StudioRuntime) -> F + Send + 'static)
    -> Result<ModelsReadHandle<S>, BridgeError>
where S: ModelsRead, F: Future<Output = anyhow::Result<S>> + Send + 'static {
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(bridge.subscriptions.next_id(), bridge.shutdown.child_token());
    let owner = Arc::new(ReadOwner { task: task.clone(), source: Mutex::new(None) });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        let source = match open(bridge.studio.clone()).await {
            Ok(source) => Arc::new(source),
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        // Retain cleanup ownership even when close already won admission. This is not a public
        // handoff: queries still need the task guard, and a late scope is closed below.
        *producer.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
        let installed = producer.task.admit(|| {
            source.ensure_open()?;
            Ok(source.identity())
        });
        match installed {
            Ok(identity) => {
                if opened.send(Ok(identity)).is_err() { producer.request_close(); }
            }
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(error));
            }
        }
        producer.task.cancel().cancelled().await;
        source.request_close();
        match source.close().await.outcome {
            FeedCloseOutcome::Clean => {
                producer.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
            }
            FeedCloseOutcome::Unresolved { issues } => {
                for issue in issues { producer.task.record_cleanup_issue(issue.into()); }
            }
        }
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = match ready.await {
        Ok(result) => result?,
        Err(_) => {
            owner.request_close();
            return Err(pl_protocol::studio::StudioError::internal().into());
        }
    };
    let handle = ModelsReadHandle { owner, registry: &bridge.subscriptions, identity: identity.into() };
    opening.0.take();
    Ok(handle)
}

impl<S: ModelsRead> ModelsReadHandle<S> {
    pub(super) fn identity(&self) -> BridgeProductReadScopeIdentity { self.identity.clone() }

    /// Runtime's synchronous query registration linearizes with native close on the same task
    /// guard. The returned future is the original owned ReadCalls query, not another task/pool.
    pub(super) fn query<F>(&self, query: impl FnOnce(&S) -> F) -> Result<F, BridgeError> {
        self.owner.task.admit(|| {
            let source = self.owner.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone().ok_or_else(closed)?;
            source.ensure_open()?;
            Ok(query(&source))
        })
    }

    pub(super) fn request_close(&self) { self.owner.request_close(); }

    pub(super) async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let outcome = if self.owner.task.wait_stopped().await.is_ok() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues: self.owner.task.close_issues() }
        };
        Ok(BridgeFeedCloseReport { feed_id: self.identity.scope_id.clone(), outcome })
    }
}

impl<S: ModelsRead> Drop for ModelsReadHandle<S> {
    fn drop(&mut self) { self.request_close(); }
}

impl<S: ModelsRead> ReadOwner<S> {
    fn request_close(&self) {
        self.task.signal_cancel();
        let source = self.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone();
        if let Some(source) = source { source.request_close(); }
    }
}

impl<S: ModelsRead> TypedFeedResource for ReadOwner<S> {
    fn release_after_join(&self) {
        let source = self.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        drop(source);
    }
}
