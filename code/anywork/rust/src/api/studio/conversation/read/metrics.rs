//! Concrete native immutable identity connection, supervised from opening through true query join.
use std::sync::{Arc, Mutex};

use pl_protocol::studio::{FeedCloseOutcome, StudioError, StudioErrorCode};
use pl_studio_runtime::StudioMetricsIdentityRead;
use tokio::sync::oneshot;

use crate::api::studio::bridge_runtime::current_bridge;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use super::super::identity::{BridgeMetricsIdentityRef, BridgeThreadFacetStamp};
use super::values::BridgeMetricsIdentityReadHeader;

struct MetricsReadOwner {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<StudioMetricsIdentityRead>>>,
}

pub struct BridgeMetricsIdentityReadConnection {
    owner: Arc<MetricsReadOwner>,
    registry: &'static BridgeTaskRegistry,
    scope_id: String,
}

pub async fn open_metrics_identity_read(thread_id: String, reference: BridgeMetricsIdentityRef,
    origin: BridgeThreadFacetStamp) -> Result<BridgeMetricsIdentityReadConnection, BridgeError> {
    let bridge = current_bridge().ok_or_else(|| BridgeError::from(StudioError::new(
        StudioErrorCode::NotInitialized, "Studio runtime is not initialized", false)))?;
    let task = TypedFeedTask::new(bridge.subscriptions.next_id(), bridge.shutdown.child_token());
    let owner = Arc::new(MetricsReadOwner { task: task.clone(), source: Mutex::new(None) });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    task.start(async move {
        // The original runtime call is retained; cancellation cannot abandon a late native scope.
        let source = match bridge.studio.open_metrics_identity_read(thread_id, reference.into(), origin.into()).await {
            Ok(source) => Arc::new(source),
            Err(error) => {
                producer.task.signal_cancel();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        let installed = producer.task.admit(|| {
            source.ensure_open()?;
            *producer.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
            Ok(source.identity().scope_id)
        });
        match installed {
            Ok(scope_id) => {
                if opened.send(Ok(scope_id)).is_err() { producer.task.signal_cancel(); }
            }
            Err(error) => {
                let _ = opened.send(Err(error));
                producer.task.signal_cancel();
            }
        }
        producer.task.cancel().cancelled().await;
        let report = source.close().await;
        match report.outcome {
            FeedCloseOutcome::Clean => {
                producer.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
            }
            FeedCloseOutcome::Unresolved { issues } => {
                // The runtime registry retains the original material and failed task owners too.
                for issue in issues { producer.task.record_cleanup_issue(issue.into()); }
            }
        }
    })?;
    let scope_id = match ready.await {
        Ok(result) => result?,
        Err(_) => {
            owner.task.signal_cancel();
            return Err(StudioError::internal().into());
        }
    };
    Ok(BridgeMetricsIdentityReadConnection { owner, registry: &bridge.subscriptions, scope_id })
}

impl BridgeMetricsIdentityReadConnection {
    pub async fn header(&self) -> Result<BridgeMetricsIdentityReadHeader, BridgeError> {
        // Runtime query registration occurs inside the same native admission guard as close.
        let query = self.owner.task.admit(|| Ok(self.owner.source()?.header()))?;
        Ok(query.await?.into())
    }

    pub async fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<BridgeTextChunk, BridgeError> {
        let query = self.owner.task.admit(|| Ok(self.owner.source()?.text(field_id, offset, max_bytes)))?;
        Ok(query.await?.into())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) { self.owner.task.signal_cancel(); }

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let stopped = self.owner.task.wait_stopped().await;
        let outcome = if stopped.is_ok() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues: self.owner.task.close_issues() }
        };
        Ok(BridgeFeedCloseReport { feed_id: self.scope_id.clone(), outcome })
    }

    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> { self.close().await }
}

impl Drop for BridgeMetricsIdentityReadConnection {
    fn drop(&mut self) { self.request_close(); }
}

impl MetricsReadOwner {
    fn source(&self) -> Result<Arc<StudioMetricsIdentityRead>, BridgeError> {
        self.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone().ok_or_else(closed)
    }
}

impl TypedFeedResource for MetricsReadOwner {
    fn release_after_join(&self) {
        let source = self.source.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        drop(source);
    }
}
